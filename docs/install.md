# 天翼云电脑 (tyydn) — NixOS 小白安装指南

> 适用对象：刚装好 **NixOS 26.05 (x86_64)**、现在坐在命令行界面 (TTY) 前、啥也不会的你。
> 跟着一步步敲命令即可，每一步都写了「应该看到什么」。全程不需要理解 Nix，会复制粘贴就行。
>
> 已在本机 **NixOS 26.05 / Nix 2.34.9 / x86_64-linux** 上用真实 `nixos-rebuild` 验证过
> （客户端 + 守护进程 + GNOME/Xfce 会话均正常运行）。
>
> 预计耗时：30–60 分钟（第一次主要耗在等网络下载）。

---

## 开始之前：确认前提

- NixOS 已装好、能进命令行。`nixos-version` 应输出 `26.05`（旧版本先升级再装，见附录 C-11）。
- x86_64 机器：`uname -m` 输出 `x86_64`。
- 系统盘至少留 **5 GB** 空闲（`df -h /`）。
- 能上外网（要访问 github.com）。
- 用**普通用户**登录（不是 root）。下面用 `alice` 举例，**全程把 alice 换成你自己的用户名**。
- 本指南假设 `/etc/nixos/flake.nix` 存在（26.05 ISO 默认会生成）。
  不存在的老系统看**附录 D**。

## 第 0 步：检查环境（1 分钟）

```sh
whoami          # 你的用户名（下面都叫它 alice）
uname -m        # 要输出 x86_64
hostname        # 记下来！第 5 步要用
sudo -V         # 输出版本号 = 你的 sudo 正常；报 sudoers 错 → 附录 C-1
nixos-version   # 26.05
passwd          # 设个密码（提示 New password: 时输入两次，屏幕上不显示是正常的）
```

再确认一件事：打开 `/etc/nixos/flake.nix`（`cat /etc/nixos/flake.nix`），
里面的 `nixosConfigurations.<名字>` 的「名字」**必须等于 `hostname` 的输出**。
不一致的话现在就改成一致（`sudo vim /etc/nixos/flake.nix`），否则第 1 步重建会报错
（详见附录 C-2）。

> vim 用法（后面反复用到）：按 `i` 进入编辑；改完按 `Esc`，输入 `:wq` 回车保存退出；
> 不想保存输入 `:q!` 回车。

## 第 1 步：装 git / git-lfs / vim（5 分钟）

tyydn 仓库里的 168MB `.deb` 是用 **git-lfs** 存储的，而 nixpkgs 的 `git` 包**不含** lfs，
所以要 `git` 和 `git-lfs` 两个都装。

编辑 `/etc/nixos/configuration.nix`（`sudo vim /etc/nixos/configuration.nix`），
找到被注释掉的这段：

```nix
  # List packages installed in system profile.
  # environment.systemPackages = with pkgs; [
  #   vim # Do not forget to add an editor to edit configuration.nix!
  #   wget
  # ];
```

改成（去掉注释、按下面内容写）：

```nix
  environment.systemPackages = with pkgs; [
    git
    git-lfs
    vim
  ];
```

保存后重建系统：

```sh
sudo nixos-rebuild switch
```

第一次重建要下载 nixpkgs 源码和一堆包，等 1–3 分钟，
输出滚动到结尾、没有 `error` 就是成功。

验证（如果提示 `git: command not found`，**注销重新登录**再试，见附录 C-8）：

```sh
git --version && git lfs version && vim --version | head -1
```

三条都有输出 → 第 1 步完成。

## 第 2 步：下载 tyydn 仓库（含 168MB 的 .deb）

```sh
cd ~
git clone https://github.com/purplepalmdash/tyydn.git
cd tyydn
git lfs pull          # 下载真正的 .deb（LFS 对象，约 168MB）
ls -lh *.deb          # 大小应该是 ~168M
```

⚠️ 如果 `ls -lh` 显示 `.deb` 只有 **134 字节**：说明 `git lfs pull` 没跑/没下完，
重跑一遍 `git lfs pull`（下载慢可以反复重跑，见附录 C-5）。

## 第 3 步：把 .deb 放进 Nix store

厂商的 `.deb` 必须先"入库"，Nix 的构建沙箱才看得到它：

```sh
cd ~/tyydn
nix store add CtyunClouddeskPublic-x86-64-20260812062844-Release-204010003-1346.deb
```

**期望输出**（一字不差地以这个开头）：

```
/nix/store/8a6ga3ky5jrzvnq4y5mqfjw0n96hm1n7-CtyunClouddeskPublic-x86-64-20260812062844-Release-204010003-1346.deb
```

开头 16 位必须是 `8a6ga3ky5jrzvnq4y5mq` —— 包定义
（`pkgs/ctyunclouddesk/default.nix` 顶部的 `srcUrl`）写死了这个路径。
不一致 → 厂商发了新版 .deb，按附录 C-4 处理。

## 第 4 步：单独构建一遍包，先验尸（可选但推荐，10 分钟）

```sh
cd ~/tyydn
nix build
```

- 第一次会下载几百 MB 的依赖并给 ~170MB 的程序打 ELF 补丁，约 2–10 分钟。
- 成功 = 当前目录出现 `result` 链接，且没有 `error`。
- 想看构建期自检输出（ldd / 解释器 / RUNPATH / 守护进程冒烟测试全 OK）：

```sh
nix log .#packages.x86_64-linux.ctyunclouddeskpublic | tail -20
```

这步失败的话现在报错比第 7 步整系统重建时报错好排查。

## 第 5 步：改 /etc/nixos/flake.nix

`sudo vim /etc/nixos/flake.nix`，整个文件改成这样
（**`nixosConfigurations.` 后面的名字保持你原来的 hostname，见第 0 步**）：

```nix
{
  description = "My NixOS configuration";

  inputs = {
    # 新装系统默认是 nixos-unstable；
    # 改成 nixos-26.05，与 tyydn 包验证过的 nixpkgs 版本保持一致
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # tyydn（天翼云电脑）封装仓库，就是第 2 步 clone 下来的
    ctyunclouddesk.url = "path:/home/alice/tyydn";
  };

  outputs = { self, nixpkgs, ctyunclouddesk, ... }@inputs: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };   # 让 configuration.nix 里能用到 inputs
      modules = [ ./configuration.nix ];
    };
  };
}
```

三处改动：① nixpkgs 从 `nixos-unstable` 钉到 `nixos-26.05`；
② 新增 `ctyunclouddesk` 输入（指向上一步 clone 的本地目录）；
③ 新增 `specialArgs = { inherit inputs; };`（少它第 6 步会报 `inputs` 未定义）。

## 第 6 步：改 /etc/nixos/configuration.nix

`sudo vim /etc/nixos/configuration.nix`，三处改动：

**① 第一行的函数签名**，把 `...` 前面加上 `inputs`：

```nix
# 原来：
{ config, lib, pkgs, ... }:
# 改成：
{ config, lib, pkgs, inputs, ... }:
```

**② imports 列表里加一行**（新装系统的模板长这样，把 `# 天翼云电脑` 那行加进去）：

```nix
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # 天翼云电脑 (tyydn) NixOS 模块
      inputs.ctyunclouddesk.nixosModules.ctyunclouddesk
    ];
```

**③ 在文件末尾的 `}` 之前**（`system.stateVersion` 那行前面）加：

```nix
  # ---------- 天翼云电脑 (tyydn) ----------
  services.ctyunclouddesk = {
    enable = true;
    # enableDaemon = true;      # 默认 true：客户端守护进程（必需，一般不用动）
    # enableUpdater = true;     # 默认 true：厂商自更新守护进程（见附录 C-7）
    autostartUsers = [ "alice" ];        # 登录后自动启动客户端
    desktopShortcutUsers = [ "alice" ];  # 桌面放一个快捷方式
    usbPermission.users = [ "alice" ];   # USB 设备重定向权限
    # 可选：原生 X11 的 Xorg + Xfce 会话（Alt+F11 等窗口快捷键），见附录 B
    # xfceSession.enable = true;
  };
```

> 注意把两处 `"alice"` 换成你的用户名。忘了改也不会报错，但模块有个断言
> 会提示 "all users must exist in users.users"。

## 第 7 步：重建系统（5–10 分钟）

```sh
sudo nixos-rebuild switch
```

这一步会：构建 tyydn 包（第 4 步做过就快）→ 安装到系统 → 启用
`clouddesktop-daemon` 等 systemd 服务 → 给 alice 放桌面快捷方式。

- 输出结尾没有 `error` = 成功。失败了也不会弄坏系统（保留旧系统），看附录 C 排查。
- 成功结尾通常有 `activation: ...` / `copying path ...` 之类的行。

## 第 8 步：命令行验证守护进程

```sh
systemctl status clouddesktop-daemon              # 要 active (running)
systemctl status ark-update-CtyunClouddeskPublic  # 要 active (running)
systemctl status ctyunclouddesk-desktop-shortcut-alice   # 应显示 done
```

守护进程已经跑起来了（负责设备注册/任务轮询，客户端依赖它）。
GUI 客户端要等图形界面。

## 第 9 步：进图形界面，启动客户端

```sh
sudo reboot
```

（如果图形界面本来就开着，可以不重启，直接切到登录画面。）

开机登录后（GDM 登录画面输入用户名密码）：

1. **桌面**上会有「天翼云电脑」快捷方式 → 双击。
   GNOME 第一次运行会问 "Trust Executable / Allow Launching"，点允许。
2. 或者点左上角九宫格**应用菜单**，搜「天翼云电脑」。
3. 或者打开终端，直接敲 `clouddesktop-qml`。
4. 因为第 6 步配了 autostart，登录后客户端也会**自动弹出来**。

看到登录界面（二维码 + 账号登录）就算装成了，按你平时用天翼云电脑的方式登录即可。

---

## 附录 A：网络慢？加国内镜像（建议）

`/etc/nixos/configuration.nix` 里加（与本机配置一致）：

```nix
  nix.settings.substituters = [
    "https://mirrors.sjtug.sjtu.edu.cn/nix-channels/store"
    "https://cache.nixos.org"
  ];
```

然后 `sudo nixos-rebuild switch`。之后所有依赖优先走上海交大镜像，快很多。
（tyydn 包本身只有本地能构建，但它的几百个依赖都在镜像里。）

## 附录 B：（可选）原生 X11 的 Xorg + Xfce 会话

客户端是纯 X11 应用，GNOME (Wayland) 里走 XWayland 也能正常用（已验证）。
如果你想要**原生 X11** 环境（窗口管理器快捷键 Alt+Tab / Alt+F4 / Alt+F11 可用），
在 `/etc/nixos/configuration.nix` 的 `services.ctyunclouddesk` 里加：

```nix
    xfceSession.enable = true;
    xfceSession.videoDrivers = [ "modesetting" ];  # 虚拟机(QEMU virtio)用这个；
                                                   # 物理机按显卡改 intel/amdgpu/nvidia
    xfceSession.repairUsers = [ ];                # 全新用户留空即可
```

`sudo nixos-rebuild switch` 后，GDM 登录画面左下角齿轮里选 **Xfce Session** 登录。
两个桌面并存，随时可切回 GNOME。

## 附录 C：常见问题（FAQ）

1. **`sudo` 报 "alice is not in the sudoers file" / 没有 sudo**
   `configuration.nix` 里给你的用户加 `extraGroups = [ "wheel" ];`：
   `users.users."alice".extraGroups = [ "wheel" "networkmanager" ];`
   然后 `sudo nixos-rebuild switch`（先临时用 root：`sudo -s` 或切 root 终端）。
   没有密码：root 下 `passwd alice` 设置。

2. **重建报 `attribute 'xxx' was not found` / `nixosConfigurations.xxx` 找不到**
   `flake.nix` 里 `nixosConfigurations.<名字>` 的名字必须和 `hostname` 输出一致。
   不一致就改名，再重建。

3. **评估时报 `inputs' is not defined`**
   第 6 步 ①（configuration.nix 签名加 `inputs`）或第 5 步 ③（`specialArgs`）漏了一个。

4. **`nix store add` 输出的路径不是 `8a6ga3ky...` 开头（厂商换了新版 .deb）**
   两个文件要改（都在 `~/tyydn/pkgs/ctyunclouddesk/default.nix` 顶部）：
   ```sh
   sha256sum CtyunClouddeskPublic-*.deb    # → 填进 srcHash
   ```
   - `srcUrl ? "file:///nix/store/<新路径>"`：换成 `nix store add` 的新输出
   - `srcHash ? "<上面 sha256 的值>"`
   然后重跑第 4、7 步。

5. **`git lfs pull` 很慢 / 中断**
   直接重跑 `git lfs pull`（断点外的已下好的不会重复下）。
   实在不行：用浏览器直接下载仓库源码包
   `https://github.com/purplepalmdash/tyydn/archive/refs/heads/main.tar.gz`
   （GitHub 会把 LFS 文件展开成真实内容），解压后把 `.deb` 放进 `~/tyydn` 即可，
   第 3 步起照常进行。

6. **客户端点不出 / 终端里 `clouddesktop-qml` 报错**
   先 `systemctl status clouddesktop-daemon` 确认守护进程活着；
   再看 `journalctl -u clouddesktop-daemon -n 50`。
   客户端本身是单实例：第二个实例会提示 "Another App is running" 后自动退出，属正常。

7. **`enableUpdater`（厂商自更新）要不要开？**
   默认开。Nix store 只读，自更新写到 payload 里只持续到下次 `nixos-rebuild`。
   想手动控制更新就设 `enableUpdater = false;`。

8. **重建成功后 `git: command not found`**
   当前 shell 的 PATH 还是旧的：**注销重新登录**（或开个新终端）就有了。

9. **构建报 `file:///nix/store/8a6ga3ky... does not exist`**
   第 3 步漏了，或者 `nix store add` 是在另一台机器上做的（store 按机器分）。
   在**这台机器**上重跑第 3 步。

10. **连上云桌面后 Alt+Tab 没反应**
    正常现象：云会话里客户端会独占键盘把按键送给远端云电脑（标准远程桌面行为），
    退出云会话（回到登录界面）即释放。

11. **NixOS 版本不是 26.05？**
    本包针对 nixpkgs 26.05 的库布局打包。25.11 及以下建议先升级系统
    （`sudo nixos-rebuild switch` + `nix flake update`），或找维护者出对应版本。

## 附录 D：你的系统没有 /etc/nixos/flake.nix（老系统 / 非 flake 安装）

> **刚装好的新系统、连图形界面/zsh 都还没配？** → 直接用 `docs/install-noflake.md`，
> 那是从 0 开始的小白指南（非 flake 版）：GDM + GNOME + Xfce、zsh、
> 开机自动登录 / sudo 免密，一步步到客户端跑起来。

第 0–4 步照做（第 1 步重建用 `sudo nixos-rebuild switch --no-flake`）。
第 5 步跳过，第 6 步改为：

- ① 签名**不用**改（不需要 `inputs`）
- ② import 改成按路径直接引模块：
  ```nix
  imports = [
    ./hardware-configuration.nix
    (import /home/alice/tyydn/nixos/ctyunclouddesk.nix)   # 天翼云电脑 (tyydn)
  ];
  ```
- ③ `services.ctyunclouddesk` 块照抄第 6 步 ③
- 第 7 步：`sudo nixos-rebuild switch --no-flake`

## 附录 E：以后怎么更新客户端

```sh
cd ~/tyydn && git pull && git lfs pull
```

- 只是改了 NixOS 配置 → `sudo nixos-rebuild switch`
- 厂商发了新版 `.deb`（文件变了）→ 重跑第 3 步 `nix store add` +
  按附录 C-4 更新 `srcUrl`/`srcHash` → 重建
- 想让 nixpkgs 也更新（可选）→ `sudo nix flake update nixpkgs`
