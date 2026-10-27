# 架构说明

## 数据流

```
厂商 .deb ──(nix store add)──> Nix store
   │
   ▼ builtins.fetchurl (eval 期取 hash,构建期为输入)
pkgs/ctyunclouddesk/default.nix (stdenvNoCC)
   ├─ unpack:  dpkg-deb -x 只解 payload
   ├─ install: 保留 /opt/ctg 布局 + 写 .desktop(Exec/Icon 指回 store)
   ├─ fixup:   autoPatchelfHook  +  makeWrapper
   └─ check:   ldd / INTERP / RUNPATH / 守护进程冒烟
   │
   ▼
store 包 $out
   ├─ opt/ctg/CtyunClouddeskPublic/   (本体,库 RUNPATH 已补 store 目录)
   ├─ bin/{clouddesktop-qml,clouddesktop-daemon,crashpad_handler,ark-update-*}
   │    └─ makeWrapper: LD_LIBRARY_PATH=$APP/lib:<store 库目录>,PATH+libexec
   ├─ usr/bin/ark-update-*            (vendor 原始路径,供包装器引用)
   └─ share/applications/ + usr/share/applications/  (.desktop)
   │
   ▼ environment.systemPackages
/run/current-system/sw/{bin,share,lib...}  ← 桌面菜单/PATH
   │
   ▼ NixOS 模块 nixos/ctyunclouddesk.nix (services.ctyunclouddesk)
   ├─ systemd: clouddesktop-daemon / ark-update-CtyunClouddeskPublic
   ├─ tmpfiles: /var/lib/CtyunClouddeskPublic (1777)
   ├─ oneshot: 每用户 autostart / 桌面快捷方式
   └─ udev 规则 + dialout 组
```

## 为什么必须 auto-patchelf(而不是只靠 LD_LIBRARY_PATH)

1. **stub-ld**:NixOS 把 `/lib64/ld-linux-x86-64.so.2` 做成 stub ELF。
   厂商二进制 `INTERP` 指向该通用路径 → 直接 `execve` 时由 stub 代跑,退出码 127,
   `systemd` 报 `status=127`。`autoPatchelfHook` 把 `INTERP` 改写为
   `$glibc/lib/ld-linux-x86-64.so.2`。
2. **传递依赖**:loader 对每个 `.so` 单独按"自身 RUNPATH → LD_LIBRARY_PATH →
   默认路径"解析其 `NEEDED`。厂商 `lib/*.so` 的 RUNPATH 只有 `$ORIGIN/lib`
   (且 `$ORIGIN` 解析到 store 路径),它们引用的系统库(libGL、glib、dbus……)
   必须写进**这些 .so 的 RUNPATH**。auto-patch-elf 对每个"解析到了依赖"的
   ELF 追加依赖所在目录;前提是构建时能按 soname 找到这些目录。
3. **vendor 库优先**:所有解析都先走 `$ORIGIN/lib`(RUNPATH 首段 + wrapper 的
   `LD_LIBRARY_PATH` 首段),store 库只兜底,不顶替。

## nixpkgs 26.05 的 output 布局(踩坑重灾区)

`runtimeLibs` 必须精确到**含 .so 的那个 output**:

| 库 | 属性 | 说明 |
| --- | --- | --- |
| glib/gio/gobject | `pkgs.glib.out` | 默认属性已是 `bin`(只有工具) |
| dbus | `pkgs.dbus.lib` | 默认 out 无 libdbus-1 |
| fontconfig | `pkgs.fontconfig.lib` | 同上 |
| xz (liblzma) | `pkgs.xz.out` | 默认 bin |
| sqlite3 | `pkgs.sqlite.out` | 默认 bin |
| libxslt | `pkgs.libxslt.out` | 默认 bin |
| libudev | `pkgs.systemdMinimal` | `libudev0-shim` 只提供 `.so.0` |
| libv4l2 | `pkgs.v4l-utils.lib` | |
| libuuid | `pkgs.libuuid.lib` | |
| Qt 插件用的额外 xcb 库 | `pkgs."libxcb-wm"` 等 | 顶层属性名带连字符,不能用函数参数名,经 `pkgs` 参数取 |

实现方式:把这些派生对象**同时**放进
`nativeBuildInputs`(它们的 `/lib` 进 auto-patch-elf 的 `--libs` 检索缓存,
从而写进各 ELF 的 RUNPATH)与 `runtimeDependencies`(动态可执行文件再前置兜底)。

## 构建期自检 (checkPhase)

`phases = [ unpackPhase patchPhase installPhase fixupPhase checkPhase ]`
(**check 在 fixup 之后**,否则 `$out` 里的 ELF 还没被 patch,`ldd` 检查是假阳性):

1. 6 个入口 `ldd` 无 `not found`(wrapper 环境 + RUNPATH)
2. `readelf -l` 的 `INTERP` 指向 store glibc
3. 入口 `RUNPATH` 含 store 库目录
4. 沙箱可写 `/var` 时:`clouddesktop-daemon -e` 跑 10s(rc=124 视为存活)

## 已知限制

- 客户端只支持 X11/xcb:GNOME Wayland 会话经 XWayland 可用;
  纯 Wayland 启动需 X 认证 cookie(`~/.Xauthority` 或
  `$XDG_RUNTIME_DIR/.mutter-Xwaylandauth.*`)。
  本机已配 Xorg + Xfce 作为原生 X11 会话(`services.xserver.desktopManager.xfce`,
  另需把各 Xfce 包的 `etc/xdg` 加入 `XDG_CONFIG_DIRS`,详见 README “X11 环境”一节)。
- store 只读:vendor 自更新写入 `/opt/ctg` 不会持久;以换 deb 升级为准。
- 厂商私有云补丁(cloudcenterm 等)仅特定 ODM 镜像触发,public 版自动跳过。
- 守护进程状态目录 `/var/lib/CtyunClouddeskPublic`(1777)+
  用户级 `~/.local/share/CtyunClouddesk{,Daemon}` 由厂商自建,模块只建共享目录。
