# 天翼云电脑 (tyydn) NixOS 小白安装指南 —— 非 flake 版

> 适用：新装的 **NixOS 26.05 (x86_64)**，**非 flake 安装**（`/etc/nixos/` 下只有
> `configuration.nix` 和 `hardware-configuration.nix`，**没有** `flake.nix`），
> 现在坐在 TTY 命令行前、啥也不会的你。
>
> 这一份从 0 配齐：**图形界面 (GDM + GNOME + Xorg/Xfce) + zsh + 免密（开机自动登录、sudo 免密）
> + 天翼云电脑客户端**。全部与参考机（NixOS 26.05 / Nix 2.34.9，真实运行环境）配置一致，
> 每一步都写了「应该看到什么」。
>
> 全程只需要会复制粘贴 + 按几个快捷键。预计 40–90 分钟（大头是下载）。

## 第 0 步：确认环境（1 分钟）

```sh
whoami        # 你的用户名，下面举例都用 alice，全程把 alice 换成你的名字
uname -m      # 必须输出 x86_64
nixos-version # 应该是 26.05
sudo -V       # 输出版本号 = sudo 可用；报 "not in the sudoers file" 见附录 FAQ-1
ls /etc/nixos/# 应该只有 configuration.nix 和 hardware-configuration.nix（+ 可能一个 .bak）
              # 如果看到 flake.nix → 你其实是 flake 系统，用 docs/install.md
```

记两样东西备用：你的用户名、你的 home 目录（`echo $HOME`，一般是 `/home/alice`）。

**nano 编辑器用法**（后面反复用到）：`Ctrl+End` 跳到文件末尾；
改完按 `Ctrl+O` → `Enter` 保存；`Ctrl+X` 退出。

## 第 1 步：图形界面 + zsh + 免密 + 常用工具（一次改完）

### 1.1 先检查，避免重复定义

```sh
grep -nE '^\s*(services\.(displayManager|desktopManager|xserver|pipewire|pulseaudio)|programs\.zsh|security\.(sudo|rtkit)|environment\.systemPackages|nix\.settings|nixpkgs\.config)' /etc/nixos/configuration.nix
```

- 没有输出，或输出的每行在 `NNN:` 后面是 `#` 开头 → 干净，直接往下。
- 有**不带 `#`** 的行（说明装系统时已经开了某些项）→ `sudo nano /etc/nixos/configuration.nix`
  在那些行行首加 `#` 注释掉（`services.pipewire = { ... };` 这种整块的要连 `{}` 内一起注释），
  然后继续。

### 1.2 改三处已有内容

`sudo nano /etc/nixos/configuration.nix`：

1. 找到 `time.timeZone = "America/New_York";` 这行（`Ctrl+W` 输入 `timeZone` 搜索），
   改成：`time.timeZone = "Asia/Shanghai";`
2. 找到 `i18n.defaultLocale = "en_US.UTF-8";`，改成：
   `i18n.defaultLocale = "zh_CN.UTF-8";`
3. 找到你的用户块（`Ctrl+W` 搜 `users.users`），把整块替换成：

   ```nix
     users.users."alice" = {
       isNormalUser = true;
       description = "alice";
       extraGroups = [ "networkmanager" "wheel" ];  # wheel: sudo 免密要用
       shell = pkgs.zsh;                            # 默认 shell 换成 zsh
     };
   ```

   （`alice` 换成你的用户名，`description` 写什么都行。）

### 1.3 粘贴新增配置块

nano 里按 `Ctrl+End` 跳到文件**最末尾**，找到最后的 `}`（整个文件最后一个右花括号），
在它**前面**整段粘贴：

```nix
  # ================= 本指南新增：镜像/界面/声音/自动登录/zsh/免密/工具 =================

  # Nix 下载镜像（国内快很多）
  nix.settings.substituters = [
    "https://mirrors.sjtug.sjtu.edu.cn/nix-channels/store"
    "https://cache.nixos.org"
  ];

  # 允许使用非自由软件
  nixpkgs.config.allowUnfree = true;

  # 图形界面：GDM 登录管理器 + GNOME 桌面（Wayland）
  # （中文字体、显卡驱动会随 GDM 自动装上，不用单独配）
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # 免密登录①：开机不输密码直接进桌面
  services.displayManager.autoLogin = {
    enable = true;
    user = "alice";
  };

  # 中文键盘布局
  services.xserver.xkb = {
    layout = "cn";
    variant = "";
  };

  # 声音（如果 1.1 检查发现 pipewire 块本来就开着，这三行就不用管了）
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # zsh + oh-my-zsh（git 补全、目录跳转；输入时灰色历史提示，按 → 补全）
  programs.zsh = {
    enable = true;
    ohMyZsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [ "git" "z" ];
    };
    autosuggestions.enable = true;
  };

  # 免密登录②：wheel 组用户 sudo 不再要密码
  security.sudo.wheelNeedsPassword = false;

  # 常用工具
  environment.systemPackages = with pkgs; [
    git
    git-lfs
    vim
  ]
    # Xfce 的开始菜单（后面第 5 步会装 Xfce；nixpkgs 的 Xfce 模块不带菜单插件）
    ++ (with pkgs.xfce; [ xfce4-whiskermenu-plugin ]);

  # 浏览器（登录云电脑/上网要用）
  programs.firefox.enable = true;
```

保存退出（`Ctrl+O` → `Enter` → `Ctrl+X`）。

### 1.4 重建系统

```sh
sudo nixos-rebuild switch
```

第一次要下载 GNOME 全家桶（约 1–2 GB），用 10–30 分钟（取决于网速）。
输出滚到结尾、**没有 `error`** 就是成功（中途有 `warning` 不用管）。

### 1.5 重启进图形界面

```sh
sudo reboot
```

开机后**不输密码自动登录进 GNOME 桌面**（免密登录生效了）。

进桌面后验证（左上角 九宫格/Activities 搜 `Terminal` 开终端，或按 `Ctrl+Alt+T`）：

```sh
echo $SHELL           # 应输出 /run/current-system/sw/bin/zsh
sudo ls /home         # 直接列出内容、不问密码 = sudo 免密 OK
```

提示符应该是 `alice@主机名:~$` 这种带颜色的（oh-my-zsh 主题）。
全部 OK → 第 1 步完成。

## 第 2 步：下载 tyydn 仓库（含 168MB 的 .deb）

桌面终端里：

```sh
git lfs install
cd ~
git clone https://github.com/purplepalmdash/tyydn.git
cd tyydn
git lfs pull          # 下载真正的 .deb（LFS 大文件，约 168MB，稍慢）
ls -lh *.deb
```

**应该看到**：`-rw-r--r-- ... 168M ... CtyunClouddeskPublic-x86-64-....deb`
⚠️ 如果 `.deb` 只有 **134 字节**：`git lfs pull` 没下完，重跑一遍 `git lfs pull`
（FAQ-3 有断点续传说明和浏览器直下备选）。

## 第 3 步：把 .deb 放进 Nix store

```sh
nix --extra-experimental-features "nix-command" store add CtyunClouddeskPublic-x86-64-20260812062844-Release-204010003-1346.deb
```

整行复制（命令很长）。开头的 `--extra-experimental-features "nix-command"` 不能省：
全新非 flake 26.05 默认没开 `nix-command` 这个 Nix 特性，少了它会报
`error: experimental Nix feature 'nix-command' is disabled`。

**应该看到**（开头 16 位必须是 `8a6ga3ky5jrzvnq4y5mq`）：

```
/nix/store/8a6ga3ky5jrzvnq4y5mqfjw0n96hm1n7-CtyunClouddeskPublic-x86-64-20260812062844-Release-204010003-1346.deb
```

开头不对 → 厂商发了新版 .deb，按 FAQ-4 处理。

## 第 4 步（可选）：单独构建一遍包，提前验尸

```sh
cd ~/tyydn
nix --extra-experimental-features "nix-command flakes" build
```

- 开头 `--extra-experimental-features "nix-command flakes"` 不能省（原因同上：
  全新非 flake 26.05 默认两个特性都没开；这条命令两个都要——`nix build` 本身
  要 `nix-command`，在当前目录里把仓库当 flake 构建还要 `flakes`）。
- 第一次下载依赖 + 给 ~170MB 程序打 ELF 补丁，约 5–15 分钟。
- 成功 = 当前目录出现 `result` 链接、没有 `error`。
- 想看构建自检输出（ldd/解释器/RUNPATH/守护进程冒烟测试全 OK）：
  `nix --extra-experimental-features "nix-command flakes" log .#packages.x86_64-linux.ctyunclouddeskpublic | tail -20`

这步失败现在报错，比第 6 步整系统重建时报错好排查。跳过也可以。

## 第 5 步：把 tyydn 模块加进系统

```sh
sudo nano /etc/nixos/configuration.nix
```

**① 改 imports**（文件开头附近，`Ctrl+W` 搜 `imports`）：

```nix
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # 天翼云电脑 (tyydn) NixOS 模块
      (import /home/alice/tyydn/nixos/ctyunclouddesk.nix)
    ];
```

（路径用你第 0 步记的 home 目录 + `/tyydn`。）

**② 在文件最后的 `}` 之前**再粘贴一块：

```nix
  # ---------- 天翼云电脑 (tyydn) ----------
  services.ctyunclouddesk = {
    enable = true;
    # enableDaemon / enableUpdater 默认都是 true（客户端守护进程 + 厂商自更新），不用写
    autostartUsers = [ "alice" ];         # 登录后自动启动客户端
    desktopShortcutUsers = [ "alice" ];   # 桌面放一个快捷方式
    usbPermission.users = [ "alice" ];    # USB 设备重定向权限
    # 原生 X11 环境：客户端是纯 X11 应用，配一个 Xorg + Xfce 会话最稳
    xfceSession = {
      enable = true;
      # videoDrivers 默认 [ "modesetting" ]：虚拟机/大多数机器直接可用；
      # 物理机老款 NVIDIA 独显可改成 [ "nvidia" ]
    };
  };
```

保存退出。

## 第 6 步：重建 + 重启

```sh
sudo nixos-rebuild switch
```

（第 4 步构建过就很快；没构建过约 5–15 分钟。）结尾没有 `error` = 成功。

```sh
systemctl status clouddesktop-daemon              # 要 active (running)
systemctl status ark-update-CtyunClouddeskPublic  # 要 active (running)
systemctl status ctyunclouddesk-desktop-shortcut-alice   # 应显示 done
```

（第三条把 `alice` 换成你的用户名。）

```sh
sudo reboot
```

## 第 7 步：进桌面，启动客户端

重启后自动登录，这次默认进 **Xfce（原生 X11）** 桌面（为这个客户端准备的）。

1. **桌面**上有「天翼云电脑」图标 → 双击。
   第一次 Thunar 可能问 "Trust / Allow"，选信任/允许。
2. 或者点左上角 Whisker 开始菜单，搜「天翼云电脑」。
3. 或者终端里直接敲 `clouddesktop-qml`。
4. 因为第 5 步配了 autostart，登录后它也会自己弹出来。

看到登录界面（二维码 + 账号登录）= 装成了。

想回 GNOME：注销 → GDM 画面**左下角齿轮** → 选 `GNOME` 登录（两个桌面并存，随时切）。
想让 GNOME 变回默认：`configuration.nix` 加一行
`services.displayManager.defaultSession = "gnome";` 再 `sudo nixos-rebuild switch`。

---

## 附录：常见问题（FAQ）

1. **`sudo: alice is not in the sudoers file`**
   第 1 步 1.2 的用户块里确认有 `extraGroups = [ "networkmanager" "wheel" ];`，重建。
   实在进不去 sudo：GDM 登录画面按 `Ctrl+Alt+F2` 切 TTY 用 root？（没密码就先
   `sudo -i` 用有权限的账号，或安装时留的 root 密码。）

2. **重建报 `attribute 'xxx' was defined multiple times`**
   1.1 的检查没做干净：把文件里**重复的那一行**（不是注释的）行首加 `#`。
   用 `grep -nE '^\s*(services\.|programs\.|security\.|environment\.systemPackages|nix\.)' /etc/nixos/configuration.nix`
   逐个查。

3. **`git lfs pull` 很慢 / 断了**
   直接重跑 `git lfs pull`，已下好的不重复下。
   实在不行：浏览器下载
   `https://github.com/purplepalmdash/tyydn/archive/refs/heads/main.tar.gz`
   （GitHub 会把 LFS 展开成真实文件），解压后把 `.deb` 拷进 `~/tyydn/`，第 3 步照常。

4. **`nix store add` 输出不以 `8a6ga3ky5jrzvnq4y5mq` 开头（厂商新版 .deb）**
   改 `~/tyydn/pkgs/ctyunclouddesk/default.nix` 顶部两行：
   ```sh
   sha256sum CtyunClouddeskPublic-*.deb    # 结果填进 srcHash
   ```
   `srcUrl ? "file:///nix/store/<nix store add 的新输出>"`、
   `srcHash ? "<sha256 结果>"`，然后重跑第 4、6 步。

5. **sudo 还要密码**
   `id` 看输出里有没有 `wheel` 组；`grep -n wheelNeedsPassword /etc/nixos/configuration.nix`
   确认是 `false` 且没被注释。改完重建 + **注销重新登录**。

6. **终端还是 bash 提示符**
   当前 shell 是旧的：**注销重新登录**（或开个新终端）就变 zsh 了。

7. **加了图形界面后开机黑屏/卡在转圈**（老显卡 GNOME Wayland 带不动）
   TTY 里 `sudo nano /etc/nixos/configuration.nix`，把
   `services.desktopManager.gnome.enable = true;` 行首加 `#`，重建。
   只留 Xfce（第 5 步的 Xorg 会话）也能用。

8. **云桌面里 Alt+Tab / Alt+F4 没反应**
   正常：云会话里客户端独占键盘，把按键送给远端云电脑（远程桌面标准行为），
   退出云会话（回登录界面）即释放。

9. **客户端打不开 / `clouddesktop-qml` 报错**
   `systemctl status clouddesktop-daemon` 要 running；
   `journalctl -u clouddesktop-daemon -n 50` 看日志。
   客户端是单实例：再开一个会提示 "Another App is running" 自动退出，属正常。

10. **更新客户端**
    `cd ~/tyydn && git pull && git lfs pull`；
    .deb 没变 → `sudo nixos-rebuild switch`；
    .deb 变了 → 重跑第 3 步 + FAQ-4 → 重建。
