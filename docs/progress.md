# 进度记录

目标:天翼云电脑 (CTyun Cloud PC) 厂商 deb 在 NixOS 上以 flake + 真实
`nixos-rebuild` 方式落地并可用。环境:NixOS 26.05 (Yarara)、Nix 2.34.9、
GNOME Wayland 自动登录(用户 `test`)。

## 状态:✅ 完成并交付(2026-10-27)

交付提交:`d594220`(pkgs/模块/测试修复 + README + docs 全套)。

- [x] deb 分析(docs/deb-analysis.md)
- [x] 包定义 pkgs/ctyunclouddesk/default.nix(build 全绿)
- [x] NixOS 模块 nixos/ctyunclouddesk.nix(services.ctyunclouddesk.*)
- [x] flake / shell.nix / tests / 文档
- [x] 挂进 /etc/nixos 并 `nixos-rebuild switch` 成功
- [x] 本机实测:守护进程、自更新进程、GUI 客户端、桌面项/自启动/udev 全部生效
- [x] tests/test-local.sh 全绿(2026-10-27 03:03,日志 tests/results/)
- [x] **Xorg (X11) + Xfce 会话**:官方模块 `services.xserver.desktopManager.xfce`
      + XDG_CONFIG_DIRS 补丁,自动登录进 Xfce;客户端在原生 X11 上 GUI 验证通过
      (截图 tests/results/xorg-*.png)

## 关键问题与解决(时间线)

1. **exit 127 / stub-ld**:厂商 ELF 的 `INTERP` 指 `/lib64/ld-linux-x86-64.so.2`
   (NixOS stub ELF)。→ `autoPatchelfHook` 改写解释器为 store glibc loader。
2. **ldd 检查假阳性**:`checkPhase` 原在 `installPhase` 之前跑,`$out` 还不存在,
   `ldd` 输出 `No such file` 不含 `not found` → 误判通过。→ 自定义
   `phases = [ ... "fixupPhase" "checkPhase" ]`,check 移到 fixup 之后。
3. **传递依赖缺失**(核心卡点):auto-patch-elf 只给"解析到依赖的 ELF"补 RUNPATH;
   厂商 `lib/*.so` 仍只有 `$ORIGIN/lib`,其系统依赖(libGL、glib、dbus、
   fontconfig、xslt、lzma、sqlite3、udev……)在运行期找不到。
   根因有二:
   a. nixpkgs 26.05 的 output 布局变化:`pkgs.glib`/`xz`/`sqlite`/`libxslt`
      默认解析到 `bin` output(只有工具,没有 .so);`dbus`/`fontconfig` 的
      .so 在 `lib` output。→ runtimeLibs 全部改成精确 output
      (`glib.out`、`dbus.lib`、`fontconfig.lib`、`xz.out`、`sqlite.out`、
      `libxslt.out`、`systemdMinimal`(libudev)等)。
   b. 库目录必须进 auto-patch-elf 的检索缓存:→ runtimeLibs 同时加入
      `nativeBuildInputs`(其 /lib 成为 `--libs` 参数),auto-patch-elf 于是把
      store 目录写进**每个** ELF 与厂商 .so 的 RUNPATH;`runtimeDependencies`
      保留作可执行文件的前置兜底。
   c. 厂商 Qt5 XCB 平台插件另缺 3 个库:libxcb-icccm(在 `pkgs."libxcb-wm"`)、
      libxcb-image、libxcb-render-util。顶层属性名带连字符,无法做函数参数名,
      → 通过 `pkgs ? (import <nixpkgs> {})` 参数(callPackage 自动传入)取用。
4. **模块层错误链**(nixpkgs 26.05 迁移):
   - `types.submodule` 需 `options.enable/options.users` 形式;
   - `pkgs.gnome.gio` 不存在 → `pkgs.glib.bin`;
   - `system.path` 不能合并定义、`environment.pathsToLink` 要字符串 →
     最终用 `environment.systemPackages = [ cfg.package ]`;
   - `services.udev.extraRules` 是 `lib.types.lines` → `optionalString ... ''...''`;
   - 多行 `ExecStart = bash -c ''...''` 被 systemd 按行解析(以 `[` 开头的行
     被当 section header → "Bad message";autostart 那条则退化成只跑
     `bash -c set -e`)→ 改用 `pkgs.writeShellScriptBin` 生成单文件脚本,
     ExecStart 单行。
   - `.desktop` 只装在 `$out/usr/share/applications`,桌面数据库找不到 →
     补装 `$out/share/applications`。
5. **测试脚本**:
   - `nix build --json` 首个 store 路径是 `.drv` → 过滤;
   - `if ! (sub) | grep` 在 `set -o pipefail` 下 `!` 只作用于子 shell 段,
     无匹配时 grep rc=1 恒进 FAIL 分支 → 改为先落盘 ldd 输出再 `grep -q`;
   - GUI 冒烟:客户端纯 X11(xcb),root/跨会话跑需 X 认证 →
     自动探测 `~/.Xauthority` 或 `$XDG_RUNTIME_DIR/.mutter-Xwaylandauth.*`。

## Xorg + Xfce 会话(2026-10-27 下午,续)

目标:在原生 X11(Xorg)上运行纯 X11 的 CTyun 客户端。

1. **选 Xfce 而非 GNOME-on-Xorg**:gnome-session 50.1 只提供 wayland-sessions,
   GNOME 上 Xorg 需要自建会话文件;Xfce 是纯 X11 桌面且自带 xsessions 条目。
2. **第一次手动方案(sessionPackages + 自建 xfce.desktop)**:Xorg 能起、
   `loginctl Type=x11`、`xfce4-session` 进程在,但无窗口管理器/面板/桌面,
   首登弹 “未能载入安全会话”(zh_CN 翻译,英文 "Unable to load a failsafe session")。
3. **根因排查(读上游源码)**:
   - xfsm-manager.c:`xfsm_manager_load_failsafe()` 从 xfconf channel
     "xfce4-session" 读 `/general/FailsafeSessionName`(="Failsafe")与
     `/sessions/Failsafe/Client*_Command`(xfwm4/xfsettingsd/xfce4-panel/
     Thunar --daemon/xfdesktop);读不到就弹该对话框。
   - xfconf 的 perchannel-xml 后端:channel 文件路径 =
     `xfce4/xfconf/xfce-perchannel-xml/<channel>.xml`,通过 libxfce4util 的
     `xfce_resource_lookup_all(XFCE_RESOURCE_CONFIG, ...)` 查找,
     搜索目录 = XDG_CONFIG_HOME + **XDG_CONFIG_DIRS 逐条** + SYSCONFDIR/xdg(/etc/xdg),
     拼接方式是 `dir + "/xfce4/xfconf/..."`(无 /xdg 变体)。
   - NixOS 包把该 XML 放在 `$PKG/etc/xdg/...` → XDG_CONFIG_DIRS 必须含
     `$PKG/etc/xdg`(第一次写成 `$PKG/etc`,少一层 xdg,所以仍失败)。
   - xfconfd 不是 failsafe 会话的 client,靠 D-Bus 激活(org.xfce.Xfconf,
     服务文件在 `share/dbus-1/services/`);只有 xfconf 包在 systemPackages 里
     用户 bus 才找得到该服务文件。
4. **修法(官方模块 + 一个补丁)**:
   - `services.xserver.desktopManager.xfce.enable = true`
     (26.05 模块在 nixos/modules/services/x11/desktop-managers/xfce.nix;
     旧式 `desktopManager.session` attrset 经 bridge 生成 xsessions/xfce.desktop
     并汇入 `services.displayManager.sessionPackages`,GDM 正常识别)。
     它同时启用 programs.xfconf/programs.dconf/xdg-desktop-portal 等。
   - 补 `environment.sessionVariables.XDG_CONFIG_DIRS = map (p: "${p}/etc/xdg") ...`
     (nixpkgs 的 xfce 模块没有这一步——本机已用 xfconf-query 实证:
     带上 etc/xdg 后 channel 可读,不带则不可)。
5. **验证**:
   - `nixos-rebuild switch` 后重启 display-manager:Xorg + xfwm4 + panel +
     xfdesktop + Thunar + xfsettingsd + notifyd + screensaver 全部起来;
     `~/.config/xfce4/` 正常写入。
   - 客户端 `DISPLAY=:0 ... clouddesktop-qml` 登录界面完整渲染(见截图);
     厂商日志:llvmpipe 软渲染被检测到 → 自动软件渲染;QR 扫码接口轮询正常。
   - 桌面快捷方式(天翼云电脑)在 Xfce 桌面上可见。

## 验证证据(2026-10-27)

- `nix build` checkPhase:`ldd OK × 6`、`INTERP OK`(store glibc)、`RUNPATH OK`
- 守护进程(宿主机 + systemd):厂商日志正常(Ark start、crashpad 初始化、
  apiHost https://desk.ctyun.cn:8810、task polling、deviceId 52:54:00:C7:51:3F)
- GUI:`$PKG/bin/clouddesktop-qml` 在 XWayland 会话存活 ≥25s,
  QtWebEngine/QML 正常,轮询厂商 `api/auth/client/qrCode/getStatus`
  (codeStatus=created,登录二维码已生成)
- `systemctl is-active`:clouddesktop-daemon=active、
  ark-update-CtyunClouddeskPublic=active、autostart oneshot=active
- `/home/test/.config/autostart/CtyunClouddeskPublic.desktop` 已安装
- `/home/test/桌面/CtyunClouddeskPublic.desktop` 已安装
- `/run/current-system/sw/share/applications/CtyunClouddeskPublic.desktop` 存在
- udev 规则生效(`/etc/udev/rules.d/99-local.rules`),`test ∈ dialout`
- `tests/test-local.sh`:All local checks passed
  (tests/results/test-local-20261027-030315.log + gui.png)
- **Xorg/Xfce(2026-10-27 04:5x)**:
  - Xorg (modesetting) 运行于 tty2,`loginctl` `Type=x11`
  - Xfce 组件全起(xfwm4/panel/xfdesktop/Thunar/xfsettingsd/xfconfd/notifyd)
  - 客户端窗口 1024x768 完整渲染登录界面(QR + 账号登录),
    截图 tests/results/xorg-xfce-desktop.png / xorg-ctyun-client.png
  - 厂商日志:checkOpenGLContext → llvmpipe → "ArkCore Use software renderType"

## 全屏与快捷键排查(2026-10-27 05:1x–06:1x)

用户反馈:客户端启动后全屏,几乎挡住所有键盘快捷键,问为什么。

### 时间线

1. `xprop`:客户端窗口 = `_NET_WM_STATE_FULLSCREEN` + `_MOTIF_WM_HINTS`
   无边框 → 应用自己请求的全屏,不是 WM 加的。
2. 厂商日志 `主窗口默认全屏: true initVisibility: 5`;QML 源码
   (dist.rcc 内 `ArkAppService.qml`)硬编码 `defaultFullScreen = true`
   (非 macOS)。开关 = `ArkStorageService.getItem("defaultFullScreenMode")
   === false` 且 `ctgLockMode !== '1'`(非锁定模式)。
3. 快捷键:按住 Alt+Tab 截图 → 切换器未出现(键盘没到 WM);
   对照实验:聚焦终端时 Alt+Tab 同样无效 → **整个会话无 WM 快捷键**。
   ltrace 客户端(登录界面):仅启动时一对 `xcb_grab_server`,无持久键盘 grab。
4. 定位 Xfce 4.20 快捷键架构:libxfce4kbd-private 的 XfceShortcutsProvider
   (xfce-shortcuts-provider.c):频道 `xfce4-keyboard-shortcuts`,
   `/xfwm4/default/*`(来自 libxfce4ui 的 perchannel XML)首启时 clone 到
   `/xfwm4/custom/*` 并置 `override=true`;xfwm4 只读 custom。
   本机的 custom 为空(04:45 首次会话在 default 尚不可见时 clone,
   写入了 override=true + 空 custom 的用户文件)→ xfwm4 零快捷键。
5. 修复:
   - `/etc/nixos/configuration.nix` 的 `XDG_CONFIG_DIRS` 增加
     `pkgs.libxfce4ui`(提供 xfce4-keyboard-shortcuts.xml);
   - 删除陈旧用户频道文件;
   - 将 60 个 default 键绑定镜像写入 custom(xfconf-query --create);
   - xfwm4 live 重抓(ltrace 见 824 次 XGrabKey)。
6. 验证:Alt+Tab 切换 ✓、Alt+F4 关窗 ✓、Alt+F11 客户端退出全屏 →
   800x600 窗口,稳定(截图 tests/results/xorg-ctyun-windowed.png)。
   插曲:中途误判快捷键仍坏,实际是会话里只剩客户端一个窗口。
7. 客户端本地存储(本地 SQLite,表 data/JSON 值)预置:
   `defaultFullScreenMode=false`、`runMode='0'`。
8. 文档:README 新增"客户端全屏与快捷键问题"节;deb-analysis.md 新增
   "运行时行为"节;architecture.md 已知限制补充 libxfce4ui 快捷键说明;
   另写 `docs/publishing.md`(GitHub 发布计划)。

### 2026-10-27 08:0x — Xfce 快捷键修复收进模块选项(`xfceSession`)

用户要求"开启快捷键切换的版本"。把手写的 Xorg/Xfce 系统配置收进模块,
新增 `services.ctyunclouddesk.xfceSession`:

1. `enable` → Xorg(`videoDrivers`,默认 modesetting)+ 官方
   `desktopManager.xfce` + `displayManager.defaultSession = mkDefault "xfce"`
   + `XDG_CONFIG_DIRS`(xfce4-session/settings/panel/notifyd/thunar/garcon
   的 etc/xdg **+ libxfce4ui**——failsafe 会话 + WM 默认快捷键两个坑一并解决)。
2. `repairUsers` → 每用户 oneshot 装 autostart 条目,跑幂等修复脚本
   (`writeShellScriptBin`):`DESKTOP_SESSION != xfce` 直接退出;custom 已有
   键位(除 override 标记外)则退出;否则把可见的 `/xfwm4/default/*` 逐个
   镜像进 `/xfwm4/custom/*`(xfwm4 live 重抓)。
3. 现场 `/etc/nixos/configuration.nix` 改用模块选项(手写块删除);
   `nixos-rebuild switch` 后:会话正常、Alt+Tab/Alt+F4 验证通过。
4. **验证修复脚本全链路**:清空 60 个 custom 键 + 保留 override=true(复现
   04:45 卡死态)→ Alt+Tab 失效 → 跑脚本 → 60 键镜像 → Alt+Tab 恢复。
   过程中发现并修掉一个 bug:fast-path 计数把 `override` 标记键当成了
   键位(custom 只剩 override 时恰好就是卡死态,会误判为"已修好")。
5. 模块写法踩坑:内层 `config = mkIf ...` 块在本 nixpkgs 不被扁平化
   (`The option 'config' does not exist`)→ 把 mkIf 直接挂在选项上;
   shell 脚本里 `${VAR:-}` 在 Nix 缩进字符串里要写 `''${}`。
6. 文档:README(配置节重写 + 选项表 + 本机配置)、guide(第 2/7 步、Q5、选项表)、
   architecture(模块选项节)。

## 后续(可选)

- `nix build .#checks.x86_64-linux.ctyunclouddesk-vm`:VM 集成测试(较重)
- 升级流程:新 deb → `nix store add` → 更新 `srcUrl/srcHash` → rebuild
- 如厂商出 Wayland 构建,可去掉 X11 相关绕行(XAUTHORITY 探测等)

## 交付物清单

| 文件 | 内容 |
| --- | --- |
| `pkgs/ctyunclouddesk/default.nix` | 包定义(解包/patchelf/wrapper/自检) |
| `nixos/ctyunclouddesk.nix` | `services.ctyunclouddesk.*` 模块(含 xfceSession:Xorg+Xfce+快捷键修复) |
| `flake.nix` / `shell.nix` | flake 包/模块/示例系统/devShell;非 flake shell |
| `tests/test-local.sh` | 本机冒烟测试(全绿,日志在 tests/results/) |
| `tests/nixos-vm.nix` | NixOS VM 测试(可选跑) |
| `README.md` | 使用/配置/技术要点/Xorg+Xfce 环境(含 xfceSession 模块选项) |
| `docs/deb-analysis.md` | 厂商 deb 分析 |
| `docs/architecture.md` | 架构与踩坑说明 |
| `docs/progress.md` | 本进度记录 |
| `docs/publishing.md` | GitHub 发布计划(deb 来源/CI/发版流程/检查清单) |
| `docs/guide.md` | 小白版安装使用指南(flake/非 flake,常见操作与 FAQ) |
| `tests/results/xorg-xfce-desktop.png` | Xorg+Xfce 桌面截图(含天翼云电脑快捷方式) |
| `tests/results/xorg-ctyun-client.png` | 客户端 X11 登录界面截图 |
| `tests/results/xorg-ctyun-windowed.png` | 客户端窗口模式(Alt+F11 退出全屏后) |
