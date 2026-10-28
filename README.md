# 天翼云电脑 (CTyun Cloud PC / AI 云电脑) NixOS 打包

把厂商的 Debian 安装包(`CtyunClouddeskPublic-*.deb`,Qt5/QtWebEngine 桌面客户端)
打包成 **NixOS 原生包 + NixOS 模块**,在本机 NixOS 上直接运行客户端及其守护进程。

已在 **NixOS 26.05 (Yarara) / Nix 2.34.9** 上通过真实 `nixos-rebuild` 验证:

- `clouddesktop-daemon.service` 运行正常(厂商日志、设备注册、任务轮询均正常)
- GUI 客户端在 GNOME (Wayland, XWayland) 会话中正常启动,可进入登录界面
- 桌面菜单/快捷方式/自启动项均已安装
- 厂商自更新守护进程 `ark-update-CtyunClouddeskPublic` 运行正常

## 目录结构

```
.
├── flake.nix                  # flake:package / nixosModule / example 系统 / devShell
├── shell.nix                  # 非 flake 开发 shell
├── pkgs/ctyunclouddesk/
│   └── default.nix            # 包定义:解包 deb、auto-patch-elf、makeWrapper、自检
├── nixos/
│   └── ctyunclouddesk.nix     # NixOS 模块:services.ctyunclouddesk.*
├── tests/
│   ├── test-local.sh          # 本机冒烟测试(build/ldd/服务/GUI 存活)
│   └── nixos-vm.nix           # NixOS VM 测试
└── docs/
    ├── deb-analysis.md        # 厂商 deb 分析(目录布局/单元脚本/依赖/运行时行为)
    ├── architecture.md        # 本方案架构说明
    ├── progress.md            # 进度记录(含踩坑清单)
    └── publishing.md          # GitHub 发布计划
```

## 使用

### 1. 把厂商 deb 放进 Nix store

客户端本体是厂商的 .deb(约 168 MB),**不提交进 git**(`.gitignore` 忽略
`*.deb`)。Nix 2.3x 的沙箱构建只能看到构建输入,因此 deb 先入库:

```bash
# 从厂商官网 https://desk.ctyun.cn 下载,放到仓库根目录,保留厂商原名:
nix store add CtyunClouddeskPublic-x86-64-20260812062844-Release-204010003-1346.deb
# 输出 /nix/store/8a6ga3ky5jrzvnq4y5mqfjw0n96hm1n7-...deb
# 相同文件名 + 相同内容 ⇒ store 路径固定,与 pkgs/ctyunclouddesk/default.nix
# 里默认的 srcUrl 一致,无需改代码。
```

换了新版 deb(文件名/内容不同)后 store 路径会变,需更新
`pkgs/ctyunclouddesk/default.nix` 顶部的 `srcUrl` / `srcHash`。
(当前默认值指向 4.1.0.1346,build 204010003-1346;详见 `docs/guide.md` 2.0 节。)

### 2. 构建包

```bash
nix build                      # 含 ldd / INTERP / RUNPATH 自检
nix log .#packages.x86_64-linux.default   # 查看自检输出
```

### 3. 安装到 NixOS 系统(flake)

本仓库已作为 flake 输入挂到 `/etc/nixos`:

```bash
# /etc/nixos/flake.nix 中:inputs.ctyunclouddesk.url = "path:/home/test/Code/nixpackage"
# /etc/nixos/configuration.nix 中:
#   nixosConfigurations... imports = [ inputs.ctyunclouddesk.nixosModules.ctyunclouddesk ];
#   services.ctyunclouddesk = { enable = true; ... };

sudo nix flake update ctyunclouddesk
sudo nixos-rebuild switch --flake /etc/nixos
```

### 4. 验证

```bash
bash tests/test-local.sh
systemctl status clouddesktop-daemon
systemctl status ark-update-CtyunClouddeskPublic
```

## 模块选项 (`services.ctyunclouddesk`)

| 选项 | 默认 | 说明 |
| --- | --- | --- |
| `enable` | `false` | 总开关 |
| `package` | 本仓库包 | 客户端包 |
| `enableDaemon` | `true` | 运行 `clouddesktop-daemon.service`(客户端依赖它) |
| `enableUpdater` | `true` | 运行厂商自更新守护进程(建议按需关,store 只读) |
| `autostartUsers` | `[]` | 写入 `~/.config/autostart` 的用户列表 |
| `desktopShortcutUsers` | `[]` | 在桌面(`~/Desktop` 或 `~/桌面`)放快捷方式的用户 |
| `usbPermission.enable` | `true` | 厂商 USB 重定向 udev 规则 |
| `usbPermission.users` | `[]` | 加入 `dialout` 组的用户 |
| `xfceSession.enable` | `false` | **"开启快捷键切换的版本"**:Xorg + 官方 Xfce 会话 + XDG_CONFIG_DIRS 补丁(failsafe 会话 + WM 默认快捷键) |
| `xfceSession.videoDrivers` | `["modesetting"]` | Xorg 显卡驱动(按硬件改) |
| `xfceSession.defaultSession` | `true` | 设 `displayManager.defaultSession="xfce"`(mkDefault,用户显式值优先) |
| `xfceSession.repairUsers` | `[]` | 给哪些用户装 xfwm4 快捷键修复 autostart(首会话固化空频道的老用户需要) |

本机当前配置:

```nix
services.ctyunclouddesk = {
  enable = true;
  enableDaemon = true;
  enableUpdater = true;
  autostartUsers = [ "test" ];
  desktopShortcutUsers = [ "test" ];
  usbPermission = { enable = true; users = [ "test" ]; };
  xfceSession = {                     # Xorg + Xfce + WM 快捷键(修复已装)
    enable = true;
    videoDrivers = [ "modesetting" ]; # QEMU virtio GPU
    repairUsers = [ "test" ];
  };
};
```

## 技术要点(为什么不是"复制过去就行")

1. **NixOS 的 stub-ld**:厂商二进制 `INTERP` 指向通用路径
   `/lib64/ld-linux-x86-64.so.2`,NixOS 上该文件是个 stub ELF,直接运行退出码 127。
   必须用 `autoPatchelfHook` 把解释器指回 store 里的 glibc loader。
2. **传递依赖**:auto-patch-elf 只给"直接找到依赖的二进制"补 RUNPATH。
   厂商自带 `lib/` 里的 `.so` 也引用系统库(libGL、glib、dbus、pulse……),
   所以把全部运行时库加进 `nativeBuildInputs`,让 auto-patch-elf 把 store 库目录
   写进**每个** ELF 的 RUNPATH,同时保留厂商 `$ORIGIN/lib` 优先。
3. **nixpkgs 26.05 的 output 布局**:`pkgs.glib`/`xz`/`sqlite`/`libxslt` 默认是
   `bin` output(只有工具),运行期 `.so` 在 `out`;`dbus`/`fontconfig` 的 `.so`
   在 `lib` output。必须按 output 精确取用(详见 `docs/architecture.md`)。
4. **客户端是纯 X11 应用**(只带 xcb Qt 平台插件):GNOME Wayland 会话里要走
   XWayland,且需要会话的 X 认证 cookie(`~/.Xauthority` 或
   `$XDG_RUNTIME_DIR/.mutter-Xwaylandauth.*`)。
5. **厂商布局保留**:payload 固定在 `/opt/ctg/CtyunClouddeskPublic`,
   `makeWrapper` 生成的包装器设置 `LD_LIBRARY_PATH`(vendor 库优先)+ PATH。

## 测试

- `tests/test-local.sh`:build → 各入口 ldd → 守护进程服务状态 → GUI 存活 25s(带截图)
- `tests/nixos-vm.nix`:NixOS VM 集成测试(`nix build .#checks.x86_64-linux.ctyunclouddesk-vm`)
- 构建期自检(`checkPhase`):6 个入口 `ldd` 无 not found、`INTERP` 指向 store glibc、
  `RUNPATH` 含 store 库目录、守护进程可启动(沙箱可写 /var 时)

## X11 环境(Xorg + Xfce)

客户端是纯 X11/xcb 应用。本机原本是 GNOME Wayland;为在**原生 X11** 上
验证/使用,配置了 Xorg + Xfce(2026-10-27 已在本机 `nixos-rebuild switch`
验证通过,截图见 `tests/results/xorg-xfce-desktop.png`、
`tests/results/xorg-ctyun.png`)。

### 配置(在 `/etc/nixos/configuration.nix`)

2026-10-27 起,Xorg+Xfce+快捷键修复已收进本仓库的模块选项
**`services.ctyunclouddesk.xfceSession`**——"开启快捷键切换的版本"
就是打开这一个开关:

```nix
services.ctyunclouddesk.xfceSession = {
  enable = true;                  # Xorg + 官方 Xfce 模块 + 默认会话 xfce
  videoDrivers = [ "modesetting" ];  # QEMU virtio GPU 用 modesetting
  repairUsers = [ "test" ];        # 修复首会话固化的空快捷键频道(老用户需要)
};
```

它等价于(历史上是手写在系统配置里的):

```nix
services.xserver = {
  enable = true;
  videoDrivers = [ "modesetting" ];   # QEMU virtio GPU 用 modesetting
  desktopManager.xfce.enable = true;  # 官方 Xfce 模块(26.05 里位于
  # nixos/modules/services/x11/desktop-managers/xfce.nix;自动注册会话、
  # 装齐组件、启用 programs.xfconf/dconf/xdg-desktop-portal 等)
};
services.displayManager.defaultSession = "xfce";  # 自动登录进 Xfce(Xorg)

# 关键补丁:nixpkgs 的 xfce 模块没有把各包的 etc/xdg 加进 XDG_CONFIG_DIRS,
# 但 Xfce 4.20 的会话定义(failsafe 会话 = 首登默认桌面)与 WM 默认快捷键
# 定义(libxfce4ui)存在 $PKG/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/*.xml,
# libxfce4util 的 xfce_resource_lookup_all() 按 XDG_CONFIG_DIRS + /etc/xdg 搜索。
# 缺 xfce4-session.xml → 首启 "Unable to load a failsafe session"(未能载入安全会话);
# 缺 libxfce4ui 的 xfce4-keyboard-shortcuts.xml → 首会话的快捷键 clone 为空,
# 整个会话无 Alt+Tab/Alt+F4/Alt+F11(见下节)。
# 路径要精确到 etc/xdg(不是 etc);列表形式下系统会再拼上标准 profile 后缀,
# 不会顶掉用户自己的定义。
```

`repairUsers` 的细节:如果某用户的首次 Xfce 会话发生在快捷键定义尚不可见时,
xfconf 频道会被固化为 `override=true` + 空 `/xfwm4/custom/*`,且 provider
之后不再重新 clone——整个会话零 WM 快捷键。模块给这些用户装一个
autostart 条目,会话启动时跑一个幂等的小脚本把 `/xfwm4/default/*` 镜像进
`/xfwm4/custom/*`(xfwm4 live 重抓键位)。新用户不需要(首会话即可见)。
本机的 test 用户就是这样固化的,已现场验证:清空 60 个 custom 键复现
卡死态(Alt+Tab 失效)→ 跑修复脚本 → 60 键镜像回去 → Alt+Tab 恢复。

模块没带的可选组件(如开始菜单插件)仍由系统配置自己加:
`environment.systemPackages = with pkgs.xfce; [ xfce4-whiskermenu-plugin ];`

排查过程与依据(上游源码:libxfce4util `xfce-resource.c`、xfce4-session
`xfsm-manager.c`、xfconf `xfconf-backend-perchannel-xml.c`)见 `docs/progress.md`
"Xorg + Xfce 会话"一节。

### 登录方式

- **开机自动登录**:GDM 直接进 Xfce (Xorg) 桌面(`defaultSession = "xfce"`)。
- **选会话**:GDM 登录界面左下角齿轮/会话选择器里,`Xfce Session` = Xorg X11,
  `GNOME Wayland`/`GNOME` = Wayland。两个会话并存,可随时切换。
- 手动在虚拟终端起会话(排障用):
  ```sh
  sudo -u test env XDG_RUNTIME_DIR=/run/user/1000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
    DISPLAY=:0 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    /run/current-system/sw/bin/startxfce4
  ```

### Xorg 上的验证结果

- Xorg (modesetting) 正常启动,`loginctl` 显示 `Type=x11` 会话。
- Xfce 会话组件齐全:xfwm4、xfce4-panel、xfdesktop、Thunar --daemon、
  xfsettingsd、xfce4-notifyd、xfce4-screensaver、xfconfd。
- 客户端在 Xorg 上直接运行(无需 XWayland):
  `DISPLAY=:0 XAUTHORITY=/run/user/1000/gdm/Xauthority .../bin/clouddesktop-qml`,
  登录界面(QR 码 + 账号登录)完整渲染;厂商日志显示检测到 llvmpipe
  软渲染后自动切到软件渲染(`ArkCore Use software renderType`),运行正常。
- 单实例行为符合预期:第二个实例通过 IPC 通知首个实例后自行退出
  ("[ark] Another App is running, so I will exit")。

## 客户端全屏与快捷键问题(2026-10-27 排查)

现象:客户端启动后全屏,Alt+Tab / Alt+F4 / Alt+Space 等全局快捷键都"失效"。

### 原因一:全屏是厂商的默认行为(客户端自己设置)

- `xprop` 显示窗口带 `_NET_WM_STATE_FULLSCREEN` + `_MOTIF_WM_HINTS` 无边框
  —— 是应用自己请求的全屏,不是窗口管理器加的。
- QML 源码(打包在 `resource/dist.rcc`)`ArkAppService.qml` 里硬编码:
  非 macOS 平台 `defaultFullScreen = true`(注释:"改成 macos 默认最大化,
  其他的默认全屏")。厂商日志:`主窗口默认全屏: true initVisibility: 5`。
- 代码里有开关:`ArkStorageService.getItem("defaultFullScreenMode") === false`
  时才窗口化,且要求非锁定模式(`ctgLockMode !== '1'`)。
  存储后端是本地 SQLite:
  `~/.local/share/CtyunClouddeskPublic/QML/OfflineStorage/Databases/<hash>.sqlite`
  (表 `data`,JSON 值)。已预置 `defaultFullScreenMode=false`、`runMode='0'`。

### 原因二:快捷键其实整个会话都没配(不是被客户端"挡"了)

排查结论(逐层验证):

1. 按住 Alt+Tab 截图:窗口切换器根本没出现 → 键盘事件没到窗口管理器。
2. **对照实验:聚焦终端窗口时 Alt+Tab 也无效** → 不是客户端抢键盘。
   ltrace 客户端进程:登录界面阶段只有启动时一对 `xcb_grab_server`,
   没有持久的 `xcb_grab_keyboard`/`XGrabKeyboard`。
3. 真正原因:Xfce 4.20 的窗口管理器快捷键来自 xfconf 频道
   `xfce4-keyboard-shortcuts` 的 `/xfwm4/custom/*`(由 libxfce4kbd-private 的
   XfceShortcutsProvider 从 `/xfwm4/default/*` clone 而来,并置
   `/xfwm4/custom/override=true`)。默认值来自 libxfce4ui 包的
   `etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml`。
   nixpkgs 不把它加进 `XDG_CONFIG_DIRS`,且首次会话(配置未生效时)的
   clone 在 default 为空时执行,把 `override=true` + 空 custom 写进了用户目录
   `~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml`
   ——之后 default 可见了,但 provider 见 override=true 只读空的 custom,
   xfwm4 一个快捷键都不抓。
4. 修复:
   - `XDG_CONFIG_DIRS` 加入 `pkgs.libxfce4ui` 的 `etc/xdg`(见上方配置);
   - 删掉陈旧的用户频道文件;
   - 把 `/xfwm4/default/*` 的 60 个默认键绑定镜像写入 `/xfwm4/custom/*`
     (`xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/custom/<组合> \
      -s <值> -t string --create`),xfwm4 随即 live 重新 XGrabKey(824 次)。
5. 注意:会话里**至少要有第二个窗口**,Alt+Tab 才有得切(曾误判为快捷键仍坏,
   实际是当时只剩客户端一个窗口)。

### 验证结果(Xorg/Xfce,客户端在前台)

| 操作 | 结果 |
| --- | --- |
| Alt+Tab | 客户端 ↔ 终端窗口正常切换 ✓ |
| Alt+F4 | 关闭活动窗口(实测关闭终端窗口)✓ |
| Alt+F11 | 客户端退出全屏 → 800x600 窗口,面板/任务栏可见,状态稳定 ✓ |

截图:`tests/results/xorg-ctyun-windowed.png`(窗口模式)。

补充:连上云桌面会话后,客户端会主动 XGrabKeyboard 独占键盘(把组合键
送给远端云电脑,标准远程桌面行为),本地快捷键此时被独占属设计如此;
退出会话(回到登录界面)即释放(已用 ltrace 验证登录界面阶段无键盘 grab)。
