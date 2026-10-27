# 发布到 GitHub 的计划

状态:**计划**(2026-10-27)。仓库目前为本地 git(19 commits,无 remote),
flake/module/包/测试/文档齐备,`flake.lock` 已提交。

## 现状盘点

| 项 | 状态 |
| --- | --- |
| flake.nix / flake.lock | 有,lock 已跟踪 |
| 包定义 | `pkgs/ctyunclouddesk/default.nix`,`srcUrl` 指向**本机 nix store** 的 `file:///nix/store/...` |
| .deb 文件 | 168MB,**已提交在仓库根目录** |
| NixOS 模块 | `services.ctyunclouddesk`,`package` 选项带默认值,自包含 |
| 测试 | `tests/test-local.sh`(本机全绿)+ `tests/nixos-vm.nix`(可选 VM) |
| LICENSE/NOTICE/CI | 无 |

## A. 必做改动

### 1. .deb 来源(最关键)

`file:///nix/store/...` 只在本机有效。方案:**按版本上传 GitHub Release asset**
(单 asset 上限 2GB,仓库 asset 总量计 4GB 限额,168MB 无压力;
raw.githubusercontent 对 >100MB 文件不可靠,不选)。

- `pkgs/ctyunclouddesk/default.nix` 改为 `finalAttrs` 风格,
  `srcUrl` 默认指向
  `https://github.com/<owner>/ctyunclouddesk-nix/releases/download/v<version>/<文件名>`;
  保留 `srcUrl/srcHash` 参数,本地开发继续可
  `callPackage ... { srcUrl = "file:///nix/store/..."; }` 覆盖。
- 把 168MB 的 deb 从仓库根移走(直接删文件提交即可;初版历史不必重写,
  或 `git filter-repo --invert-paths` 清理历史)。
- 发版:`gh release create vX.Y.Z <deb> --title ... --notes ...`。

### 2. 许可证/归属

- 仓库代码:加 `LICENSE`(建议 MIT)。
- 加 `NOTICE`:厂商二进制为专有(EULA 见 desk.ctyun.cn),本仓库只含
  重新打包 + Nix 胶水代码;`meta.license = licenses.unlicense` 已如实标注。
- README 明确:构建产物含 vendor 专有组件,自用没问题,二次分发以
  vendor EULA 为准。

### 3. README 增加"外部用户快速上手"

```nix
# flake.nix
inputs.ctyunclouddesk.url = "github:<owner>/ctyunclouddesk-nix";

# configuration.nix
imports = [ inputs.ctyunclouddesk.nixosModules.ctyunclouddesk ];
services.ctyunclouddesk = {
  enable = true;
  autostartUsers = [ "$USER" ];
  desktopShortcutUsers = [ "$USER" ];
  usbPermission.users = [ "$USER" ];
};
```

- X11 注意事项(纯 X11/xcb;Wayland 需 X 认证 cookie,或按 README
  "X11 环境"一节配 Xorg+Xfce)。
- 用 Xfce 的用户:说明 `XDG_CONFIG_DIRS` 需含 `pkgs.libxfce4ui` 的
  `etc/xdg`(WM 快捷键定义,见 README "全屏与快捷键"一节)。

### 4. CI(.github/workflows/ci.yml)

- 触发:push + PR。
- 步骤:装 nix(DeterminateSystems/setup-nix 或 nixbuildactions/nix-build),
  然后:
  1. `nix flake check`(轻)
  2. `nix build .#x86_64-linux`——包内 checkPhase 自带
     ldd/INTERP/RUNPATH/daemon 冒烟,构建即验证
  3. VM 测试 `nix build .#checks.x86_64-linux.ctyunclouddesk-vm`
     较重:放 `workflow_dispatch` + 周度 schedule
- 可选:缓存(nixbuildactions cache / cachalot)加速。

### 5. 发版脚本 scripts/update-deb.sh

```
用法: update-deb.sh /path/to/new.deb
  1. sha256sum
  2. dpkg-deb -f 解析 Version/包名
  3. 更新 default.nix 的 version/srcHash/srcUrl 文件名
  4. nix build 验证
  5. 提示:git tag v<version> && gh release create v<version> <deb>
  6. 更新 README/progress 中的版本号
```

### 6. 仓库卫生

- 根目录 168MB deb:移出(见 1)。
- `help.txt`(vendor 帮助 URL):移到 `docs/references/help.txt` 或删除。
- `tests/results/` 的 png 证据已 force-add,保留;日志仍被 ignore。
- `.gitignore` 现有规则够用。
- 提交身份统一(现 `nix <nix@local>`)。

## B. 可选

- **上游 nixpkgs**:包风格已是 nixpkgs 风格(pname/meta/hyphen attr
  经 `pkgs."libxcb-wm"` 取)。上游化需要:release-asset `src`(不依赖本仓库
  即可)、maintainer、license 讨论;vendor 专有二进制在 nixpkgs 属
  `unfree`(需 `pkgs.unfree` 分区)。
- **aarch64**:vendor deb 目前只有 x86-64,`platforms` 已如实声明。
- 发布 flake 到 registry(如登记 nix-community)非必需。

## C. 发布前检查清单

- [ ] `srcUrl` 指向 release asset,`nix build .#x86_64-linux` 在干净机器通过
- [ ] `flake.lock` 最新且已提交
- [ ] 新 NixOS VM 里用 flake input + 模块跑通(或 example configuration)
- [ ] `nix flake check` 通过
- [ ] CI 首跑全绿
- [ ] README 快速上手按新 URL 实测一遍
- [ ] Release 含 deb asset + 版本号 + changelog(可引用 docs/progress.md)
