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
    ├── deb-analysis.md        # 厂商 deb 分析(目录布局/单元脚本/依赖)
    ├── architecture.md        # 本方案架构说明
    └── progress.md            # 进度记录(含踩坑清单)
```

## 使用

### 1. 把厂商 deb 放进 Nix store

Nix 2.3x 的沙箱构建只能看到构建输入,因此 deb 先入库:

```bash
nix store add CtyunClouddeskPublic-x86-64-20260812062844-Release-204010003-1346.deb
# 记下输出的 /nix/store/<hash>-CtyunClouddeskPublic-....deb,
# 更新 pkgs/ctyunclouddesk/default.nix 顶部的 srcUrl / srcHash
```

(当前默认值已指向本机 store 中的 4.1.0.1346 版本。)

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

本机当前配置:

```nix
services.ctyunclouddesk = {
  enable = true;
  enableDaemon = true;
  enableUpdater = true;
  autostartUsers = [ "test" ];
  desktopShortcutUsers = [ "test" ];
  usbPermission = { enable = true; users = [ "test" ]; };
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

```nix
# 官方 Xfce 模块:26.05 里位于 nixos/modules/services/x11/desktop-managers/xfce.nix
# (wiki.nixos.org/wiki/Xfce 的旧路径 services.xserver.desktopManager.xfce 仍然有效)。
# 自动:注册 xfce 会话、装齐 Xfce 组件、启用 programs.xfconf(xfconfd D-Bus 服务)、
# dconf、xdg-desktop-portal 等。
services.xserver = {
  enable = true;
  videoDrivers = [ "modesetting" ];   # QEMU virtio GPU 用 modesetting
  desktopManager.xfce.enable = true;
};
services.displayManager.defaultSession = "xfce";  # 自动登录进 Xfce(Xorg)

# 关键补丁:nixpkgs 的 xfce 模块没有把各包的 etc/xdg 加进 XDG_CONFIG_DIRS,
# 但 Xfce 4.20 的会话定义(failsafe 会话 = 首登默认桌面)存在
# $PKG/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/*.xml,
# libxfce4util 的 xfce_resource_lookup_all() 按 XDG_CONFIG_DIRS + /etc/xdg 搜索。
# 不手动加的话,xfconfd 找不到 channel 文件,xfce4-session 首启读不到
# /general/FailsafeSessionName,弹 "Unable to load a failsafe session"
# (中文:未能载入安全会话)且无窗口管理器。
# 注意:路径要精确到 etc/xdg(不是 etc)。
environment.sessionVariables.XDG_CONFIG_DIRS =
  map (p: "${p}/etc/xdg") (with pkgs.xfce; [
    xfce4-session xfce4-settings xfce4-panel xfce4-notifyd thunar garcon
  ]);

# 模块没带的可选组件
environment.systemPackages = with pkgs.xfce; [ xfce4-whiskermenu-plugin ];
```

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
