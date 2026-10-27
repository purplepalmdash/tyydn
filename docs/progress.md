# 进度记录

目标:天翼云电脑 (CTyun Cloud PC) 厂商 deb 在 NixOS 上以 flake + 真实
`nixos-rebuild` 方式落地并可用。环境:NixOS 26.05 (Yarara)、Nix 2.34.9、
GNOME Wayland 自动登录(用户 `test`)。

## 状态:✅ 完成(2026-10-27)

- [x] deb 分析(docs/deb-analysis.md)
- [x] 包定义 pkgs/ctyunclouddesk/default.nix(build 全绿)
- [x] NixOS 模块 nixos/ctyunclouddesk.nix(services.ctyunclouddesk.*)
- [x] flake / shell.nix / tests / 文档
- [x] 挂进 /etc/nixos 并 `nixos-rebuild switch` 成功
- [x] 本机实测:守护进程、自更新进程、GUI 客户端、桌面项/自启动/udev 全部生效
- [x] tests/test-local.sh 全绿(2026-10-27 03:03,日志 tests/results/)

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

## 后续(可选)

- `nix build .#checks.x86_64-linux.ctyunclouddesk-vm`:VM 集成测试(较重)
- 升级流程:新 deb → `nix store add` → 更新 `srcUrl/srcHash` → rebuild
- 如厂商出 Wayland 构建,可去掉 X11 相关绕行(XAUTHORITY 探测等)
