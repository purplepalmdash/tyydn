# 厂商 deb 分析

对象:`CtyunClouddeskPublic-x86-64-20260812062844-Release-204010003-1346.deb`
(天翼云电脑 4.1.0.1346,amd64,Installed-Size ≈ 465 MiB,
maintainer clouddesktop@chinatelecom.cn)

## 1. 目录布局

| 路径 | 内容 |
| --- | --- |
| `/opt/ctg/CtyunClouddeskPublic/` | 客户端本体(QT5.15.2 + QtWebEngine) |
| 同上 `lib/` | 厂商自带全部共享库(约 244 MB),ELF `RUNPATH=$ORIGIN/lib` |
| 同上 `clouddesktop-qml` | GUI 客户端入口(QtWebEngine 桌面登录/串流界面) |
| 同上 `clouddesktop-daemon` | 常驻守护进程(`-e` 后台模式),设备注册/任务轮询 |
| 同上 `crashpad_handler` | crash 收集器 |
| 同上 `libexec/QtWebEngineProcess` | QtWebEngine 子进程 |
| 同上 `plugins/ qml/ resources/ static/ translations/` | Qt 平台插件、QML 资源等 |
| `/usr/bin/ark-update-CtyunClouddeskPublic{,d}` | 自更新工具 + 自更新守护进程 |
| `/usr/share/applications/CtyunClouddeskPublic.desktop` | 桌面条目,`Exec=/opt/ctg/.../clouddesktop-qml` |
| `/lib/systemd/system/clouddesktop-daemon.service` | `Type=simple`,`ExecStart=/opt/ctg/.../clouddesktop-daemon -e`,`Restart=always RestartSec=5` |
| `/lib/systemd/system/ark-update-CtyunClouddeskPublic.service` | `Type=forking`,`ExecStart=/usr/bin/ark-update-CtyunClouddeskPublicd`,`Restart=always KillMode=process` |

关键点:

- **纯 X11 应用**:只带 `xcb` Qt 平台插件(日志 `Available platform plugins are: xcb`),
  Wayland 会话必须走 XWayland + X 认证 cookie。
- **厂商库优先**:`$ORIGIN/lib` 在 RUNPATH 首位;缺的系统库(libGL、glib-2.0、
  dbus、pulse、fontconfig、xslt、lzma、sqlite3、nss/nspr、v4l2、udev、X11 一族……)
  必须来自系统。
- **ELF 解释器**:`/lib64/ld-linux-x86-64.so.2`(通用路径,非 NixOS 风格)。

## 2. postinst 行为(安装期副作用)

| 动作 | 说明 |
| --- | --- |
| `systemctl enable/start ark-update-CtyunClouddeskPublic` | 启动自更新守护进程 |
| `set_usb_permission`: `usermod -aG dialout <登录用户>` + 写 `/etc/udev/rules.d/99-clink.rules` | 规则内容:`SUBSYSTEM=="usb", MODE="0666", GROUP="dialout"`(USB 重定向需要) |
| `set_autostart`: 把 `.desktop` 拷进每个用户 `~/.config/autostart/`(并清理旧版 `Ctyun.desktop`/`CtyunClouddeskUniversal.desktop`) | 登录自启 |
| `copy_install_to_desktop`: 桌面快捷方式 | 桌面入口 |
| 私有云/升腾(Centerm)补丁:`public/cloudcenterm.tar.gz`、`mspad-centerm-*.tar.gz` 解到 /tmp 执行 | 特定 ODM 镜像用,public 区无这些文件时自动跳过 |
| 采集 dmidecode/OS 信息写入设备档案 | 设备指纹 |

## 3. 本方案的对应物

| postinst 动作 | NixOS 模块对应 |
| --- | --- |
| payload 装到 `/opt/ctg/...` | 保留布局:store 包内 `opt/ctg/...`,经 `environment.systemPackages` 挂到 `/run/current-system/sw` |
| 两个 systemd 单元 | `systemd.services.clouddesktop-daemon` / `ark-update-CtyunClouddeskPublic`(ExecStart 指向 store 内 makeWrapper 包装器) |
| autostart / 桌面快捷方式 | `autostartUsers` / `desktopShortcutUsers` → 每用户 oneshot 单元 |
| udev 规则 + dialout 组 | `services.udev.extraRules` + `users.users.*.extraGroups` |
| `/var/lib/CtyunClouddeskPublic`(守护进程/客户端共享状态) | `systemd.tmpfiles.rules`(`d /var/lib/CtyunClouddeskPublic 1777`) |

> 注:厂商单元名是 `ark-update-CtyunClouddeskPublic.service`(无尾缀 d),
> 可执行文件才带 d(`ark-update-CtyunClouddeskPublicd`)。模块沿用厂商单元名。

## 4. 版本升级

vendor 自更新会向 `/opt/ctg` 写新版 payload;NixOS 上该目录在 store 里只读,
更新只在当前运行中生效,`nixos-rebuild` 后回到包内版本。建议:
更新渠道以"换 deb → `nix store add` → 改 `srcUrl/srcHash` → rebuild"为准,
`enableUpdater` 可按需关闭。

## 5. 运行时行为(2026-10-27 排查记录)

- **默认全屏**:QML(`resource/dist.rcc` 内 `ArkAppService.qml`)非 macOS
  硬编码 `defaultFullScreen = true`;窗口自设 `_NET_WM_STATE_FULLSCREEN`
  + `_MOTIF_WM_HINTS` 无边框。开关:`ArkStorageService.getItem(
  "defaultFullScreenMode") === false` 且 `ctgLockMode !== '1'`(非锁定模式)。
- **本地设置存储**:SQLite
  `~/.local/share/CtyunClouddeskPublic/QML/OfflineStorage/Databases/<hash>.sqlite`,
  表 `data`(name TEXT, value TEXT,JSON 编码)。可用 sqlite3 预置键,
  如 `defaultFullScreenMode` = `false`、`runMode` = `0`(常规模式)。
- **键盘 grab**:登录界面阶段无持久 grab(ltrace 验证,仅启动时一对
  `xcb_grab_server`);主二进制含 2 处 `XGrabKeyboard@plt` 调用点,
  连上云桌面会话后独占本地键盘(把组合键送远端,远程桌面标准行为)。
- **单实例**:第二实例经 IPC 通知首实例后自行退出
  ("[ark] Another App is running, so I will exit.")。
