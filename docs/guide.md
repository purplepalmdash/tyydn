# 天翼云电脑 NixOS 上手指南(小白版)

这份指南面向**只想要"装好、能登录云电脑"**的用户。跟着做,大约 10 分钟。
全程只用终端,不需要理解 Nix 原理。

> 已在 NixOS 26.05(x86-64)上实测。24.11 / 25.05 理论相同,命令一样。
> 仓库地址下面用 `OWNER/ctyunclouddesk-nix` 占位,发布后替换成实际地址。
> 客户端本体(约 168 MB 的 .deb)**已包含在本分支仓库里**(仓库根目录,
> 厂商原文件名,无需下载),怎么入库见第 2 步的 **2.0 节**。

---

## 第 0 步:先认识一下你要装的东西

- **天翼云电脑客户端**(厂商叫 CtyunClouddeskPublic):一个登录云电脑的桌面程序,
  支持扫码 / 账号登录。
- 本方案给它装了两个后台服务:
  - `clouddesktop-daemon`——厂商要求的常驻服务,**客户端依赖它**;
  - `ark-update-*`——厂商自带的新版检查服务(不想让它自动检查新版可关,见第 8 节)。
- 客户端是 **X11 程序**。在默认的 GNOME Wayland 桌面上它通过 XWayland
  照常运行(已实测);想要原生 X11 桌面请看第 7 节(可选)。
- **客户端本体**是厂商的 .deb 安装包(约 168 MB),**本分支已包含**(仓库
  根目录,厂商原文件名)。第 2 步的 2.0 节会告诉你怎么把它放进 Nix store。

---

## 第 1 步:检查你的系统(1 分钟)

打开终端,依次执行:

```sh
# 1) 确认是 NixOS
cat /etc/os-release | head -1
# 期望输出类似:NixOS 26.05 ...

# 2) 确认你的 /etc/nixos 是不是 flake 方式(现在的新装系统基本都是)
ls /etc/nixos/flake.nix
```

- `ls` 有输出(文件存在)→ 走 **第 2 步(A 方法)**。
- `ls` 报 No such file → 你的系统是旧式非 flake 配置,走 **第 2 步(B 方法)**。

记下你的用户名(下面命令里写 `test`,换成你的):

```sh
whoami
```

---

## 第 2 步:安装

### 2.0 先把厂商 deb 放进 Nix store(A、B 两种方法都要,约 1 分钟)

客户端本体(厂商 .deb,约 168 MB)**已包含在本分支仓库里**,在仓库根目录、
厂商原文件名(文件名参与 store 路径计算,不要改名):

   ```
   CtyunClouddeskPublic-x86-64-20260812062844-Release-204010003-1346.deb
   ```

   (对应本仓库支持的客户端 4.1.0.1346。厂商下载地址为官网
   <https://desk.ctyun.cn>,本分支已带上,.deb 不用另下;若你想用自己
   下载的 .deb,文件名须与上面完全一致。)

文件在哪:

- B 方法:2.1 克隆出来的目录里就有,`/opt/src/ctyunclouddesk-nix/`;
- A 方法:flake 输入从 GitHub 拉取(拉下来的源码里包含 .deb);若本地没有
  副本,可从 GitHub 仓库页面下载这一个文件。

1. 用**普通用户**(不要用 sudo)执行,把文件放进 Nix store:

   ```sh
   nix store add /完整路径/CtyunClouddeskPublic-x86-64-20260812062844-Release-204010003-1346.deb
   ```

   输出应该是:

   ```
   /nix/store/8a6ga3ky5jrzvnq4y5mqfjw0n96hm1n7-CtyunClouddeskPublic-x86-64-20260812062844-Release-204010003-1346.deb
   ```

   相同文件名 + 相同内容,store 路径是固定的,正好和仓库里写死的 `srcUrl`
   一致,**不用改仓库里的任何文件**。若下的是新版 deb、路径对不上,见第 9 节。

2. 入库成功后,若用的是仓库外的副本(例如从 GitHub 单独下的那个),可以删掉
   (store 里有副本了);仓库根目录里那个是源,留着即可。

### A 方法:flake 系统(推荐,大多数人)

**2.1 把仓库加入 flake 输入**

用你习惯的编辑器打开 `/etc/nixos/flake.nix`,在 `inputs = { ... }` 里加一行:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";   # 已有,别动
  ctyunclouddesk.url = "github:OWNER/ctyunclouddesk-nix";  # ← 加这行
};
```

**2.2 启用模块**

编辑 `/etc/nixos/configuration.nix`,在文件开头(其他 `services.*` 附近)加:

```nix
# 天翼云电脑客户端
imports = [ inputs.ctyunclouddesk.nixosModules.ctyunclouddesk ];

services.ctyunclouddesk = {
  enable = true;
  autostartUsers = [ "test" ];        # ← 换成你的用户名
  desktopShortcutUsers = [ "test" ];  # 桌面放一个快捷方式
  usbPermission.users = [ "test" ];   # 插 U 盘/USB 设备免 sudo 授权
  # 可选:原生 X11 桌面(Xorg + Xfce)+ WM 快捷键,见第 7 步:
  # xfceSession = { enable = true; repairUsers = [ "test" ]; };
};
```

**2.3 构建并应用**

```sh
sudo nixos-rebuild switch --flake .#nixos
```

(第一次构建要编译环境,约 3–10 分钟,看到 `Done. The new configuration is ...` 就成功。)

### B 方法:非 flake 系统

**2.1 把仓库克隆到固定位置**

```sh
sudo mkdir -p /opt/src
sudo git clone https://github.com/OWNER/ctyunclouddesk-nix /opt/src/ctyunclouddesk-nix
sudo chown -R test:users /opt/src/ctyunclouddesk-nix
```

**2.2 编辑 `/etc/nixos/configuration.nix`**,加:

```nix
imports = [ /opt/src/ctyunclouddesk-nix/nixos/ctyunclouddesk.nix ];

services.ctyunclouddesk = {
  enable = true;
  autostartUsers = [ "test" ];
  desktopShortcutUsers = [ "test" ];
  usbPermission.users = [ "test" ];
  # 可选:原生 X11 桌面(Xorg + Xfce)+ WM 快捷键,见第 7 步:
  # xfceSession = { enable = true; repairUsers = [ "test" ]; };
};
```

**2.3 构建并应用**

```sh
sudo nixos-rebuild switch
```

---

## 第 3 步:验证装好了(1 分钟)

```sh
# 后台服务在跑吗?(两个都应该是 active (running))
systemctl status clouddesktop-daemon --no-pager -n 0
systemctl status ark-update-CtyunClouddeskPublic --no-pager -n 0

# 客户端命令在吗?
command -v clouddesktop-qml
# 期望输出:/nix/store/...-ctyunclouddeskpublic-.../bin/clouddesktop-qml
```

---

## 第 4 步:启动客户端,登录云电脑

**重新登录一次桌面**(注销再登录,或重启机器),然后任选:

- 桌面上有 **"天翼云电脑"图标** → 双击;
- 应用菜单(开始菜单)里搜 **"天翼云电脑"** → 点开;
- 终端里输入 `clouddesktop-qml` 回车。

出现登录窗口后:
- **扫码登录**:用天翼云 APP / 翼支付 / 微信扫码(最省事);
- **账号登录**:手机号/邮箱/账号 + 密码。

登录成功后就是云桌面,和普通 Windows 云电脑用法一致。

> 之后每次登录桌面,客户端会**自动启动**(已配置 autostart)。
> 如果看到"另一个实例正在运行"的提示,说明它已经在跑了,关掉这个即可。

---

## 第 5 步:常用操作速查

| 想干什么 | 怎么做 |
| --- | --- |
| 退出客户端 | 窗口右上角的电源/关闭按钮,或终端 `pkill -u $USER -f 'clouddesktop[-]qml'` |
| 启动客户端 | 桌面图标 / 菜单 / `clouddesktop-qml` |
| 看后台服务状态 | `systemctl status clouddesktop-daemon` |
| 看客户端日志 | 客户端自己会在 `~/.local/share/CtyunClouddeskPublic/Log/` 写日志 |
| 看服务日志 | `journalctl -u clouddesktop-daemon -n 50 --no-pager` |
| USB / U 盘被占用 | 模块已按厂商规则放开权限;若没生效,重新登录桌面(udev 规则随会话加载) |

---

## 第 6 步(可选):窗口模式启动,不全屏

客户端默认**全屏**(厂商行为)。随时按 **Alt+F11** 可以在全屏/窗口之间切换。

想让它**默认就窗口模式**(进阶,一条命令):

```sh
DB=$(ls ~/.local/share/CtyunClouddeskPublic/QML/OfflineStorage/Databases/*.sqlite | head -1)
# 需要 sqlite3:在 flake 的 environment.systemPackages 里加 pkgs.sqlite
sqlite3 "$DB" "INSERT INTO data (name,value) VALUES ('defaultFullScreenMode','false')
  ON CONFLICT(name) DO UPDATE SET value='false';"
```

(原理见 `README.md` "客户端全屏与快捷键问题"一节。)

---

## 第 7 步(可选):想要原生 X11 桌面(Xorg + Xfce)

默认 GNOME Wayland 下客户端已能正常用(走 XWayland)。如果你更喜欢
纯 X11 环境(或遇到 Wayland 兼容问题),只需再开一个开关——
"开启快捷键切换的版本"(Xorg + Xfce 会话,Alt+Tab/Alt+F4/Alt+F11 都可用):

```nix
# /etc/nixos/configuration.nix,在 services.ctyunclouddesk 里加:
  xfceSession = {
    enable = true;
    videoDrivers = [ "modesetting" ];  # QEMU/virtio GPU;物理机按显卡改
    repairUsers = [ "你的用户名" ];     # 修复过旧 Xfce 会话的快捷键残留
  };
```

```sh
sudo nixos-rebuild switch --flake .#nixos
```

登录界面选 **Xfce Session** 即进 Xorg X11 桌面(GNOME 会话仍保留,
可随时切换)。详见 `README.md` "X11 环境(Xorg + Xfce)"一节。

> 不加这个开关也能用(走 XWayland),但 Xfce 桌面下 Alt+Tab 等快捷键
> 需要模块的 XDG_CONFIG_DIRS 补丁才会生效。

---

## 第 8 节:进阶配置(模块全部选项)

编辑 `services.ctyunclouddesk` 里对应的开关:

| 选项 | 默认 | 说明 |
| --- | --- | --- |
| `enable` | false | 总开关 |
| `enableDaemon` | true | 关闭则不装 `clouddesktop-daemon`(客户端需要,一般别关) |
| `enableUpdater` | true | 厂商自更新守护进程;不想自动检查新版就设 false |
| `autostartUsers` | [] | 哪些用户登录桌面时自动启动客户端 |
| `desktopShortcutUsers` | [] | 给哪些用户桌面放快捷方式 |
| `usbPermission.enable` / `.users` | false / [] | 应用厂商的 USB udev 规则(放开 USB 设备权限) |
| `xfceSession.enable` | false | "开启快捷键切换的版本":Xorg + Xfce 会话 + WM 快捷键修复(第 7 步) |
| `xfceSession.videoDrivers` | ["modesetting"] | Xorg 显卡驱动(按硬件改) |
| `xfceSession.defaultSession` | true | 自动登录默认进 Xfce(GNOME 仍可在登录界面选) |
| `xfceSession.repairUsers` | [] | 给哪些用户装快捷键修复(之前装过 Xfce 且快捷键坏过的用户) |
| `package` | 本仓库的包 | 一般不用动 |

---

## 第 9 节:升级

厂商发布新客户端时:

```sh
# 1) 从厂商官网 desk.ctyun.cn 下载新版 deb,替换本仓库根目录里那个
#    (保留厂商原文件名;提交进仓库,保持"仓库自带"状态)
# 2) 放入 nix store,记下输出的 store 路径
nix store add /仓库根目录/CtyunClouddeskPublic-xxx.deb
# 3) 更新包里的 srcUrl(上一步的 store 路径)/ srcHash / version
#    (见 README "技术要点" / docs/progress.md)
#    —— 若仓库已按 release asset 方式发布,直接用新版仓库 tag 即可:
sudo nix flake update ctyunclouddesk
# 4) 重建
sudo nixos-rebuild switch --flake .#nixos
```

简单记:**跟着仓库版本走**——仓库出新 tag,你 `nix flake update` +
`nixos-rebuild switch` 就是新版。

---

## 第 10 节:卸载

```nix
# /etc/nixos/configuration.nix:删掉(或注释)
imports = [ inputs.ctyunclouddesk.nixosModules.ctyunclouddesk ];
services.ctyunclouddesk = { ... };
```

```sh
sudo nixos-rebuild switch --flake .#nixos
```

- 服务、快捷方式、autostart 条目随之消失;
- 用户数据(`~/.local/share/CtyunClouddeskPublic` 等)保留,
  想彻底删:注销后 `rm -rf ~/.local/share/CtyunClouddesk{,Daemon} ~/.config/CtyunClouddesk{,Daemon} ~/.local/share/CtyunClouddeskPublic`。

---

## 第 11 节:常见问题

**Q1:装完桌面没有图标?**
重新登录一次桌面(autostart/快捷方式在会话启动时安装)。
还没有就 `ls ~/桌面` 看文件在不在,在就右键"始终显示为图标"。

**Q2:客户端打开后一片黑/没窗口?**
- 确认在服务列表里:GNOME 登录界面选会话时注意 `GNOME Wayland` 还是 `GNOME`;
  两者都能跑,但窗口管理偶有差异,换一种试试。
- 终端手动跑看报错:`clouddesktop-qml 2>&1 | tail`
- Wayland 下若报 X 认证错误:
  `XAUTHORITY=$XDG_RUNTIME_DIR/.mutter-Xwaylandauth.* clouddesktop-qml`

**Q3:提示"另一个应用实例正在运行"?**
说明已有客户端在跑(可能开机自启的)。找到它:
`ps -u $USER | grep clouddesktop`,不需要就
`pkill -u $USER -f 'clouddesktop[-]qml'` 再重新打开。

**Q4:连上云桌面后,键盘 Ctrl+Alt+Del 这类组合键本地不灵?**
正常现象:云桌面会话中客户端独占键盘,把组合键送给远端(远程桌面标准行为);
退出云桌面回到登录界面即恢复。

**Q5:Xfce 桌面上 Alt+Tab 等快捷键不好使?**
确认装的是"开启快捷键切换的版本":`services.ctyunclouddesk.xfceSession.enable = true`
(含 libxfce4ui 的 XDG_CONFIG_DIRS 补丁);老用户(之前装过 Xfce)再加
`xfceSession.repairUsers = [ "你的用户名" ]` 并重新登录;且会话里至少有两个
窗口可切换。详见 `README.md` "全屏与快捷键"一节。

**Q6:重启后客户端没自动起?**
看 `systemctl --user status ctyunclouddesk-autostart-$(whoami) --no-pager`
(用户级 oneshot,负责放 autostart 条目),再确认 `~/.config/autostart/`
下有 `CtyunClouddeskPublic.desktop`。没有就重新登录一次桌面。

**Q7:U 盘插上没反应 / 提示权限?**
确认 `usbPermission.users` 里有你的用户名,且重新登录过桌面
(udev 规则对已连接设备需要重插才生效)。

---

## 还不会?看这里

- 原理与踩坑全记录:`README.md`、`docs/progress.md`
- 包是怎么打的:`docs/architecture.md`、`docs/deb-analysis.md`
- 厂商在线帮助:`help.txt` 里的链接
- 厂商官网/下载:`https://desk.ctyun.cn`
