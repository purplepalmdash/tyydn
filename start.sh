#!/bin/sh
# 天翼云电脑客户端命令行启动器(后台拉起,等效于桌面快捷方式)
#
# 用法:  仓库根目录下 ./start.sh(需已 nix build,存在 result 链接)
# 前提:  clouddesktop-daemon 服务在运行:
#         systemctl status clouddesktop-daemon
#
# 桌面会话内的终端 DISPLAY 已设好,直接跑即可;
# 纯 TTY/SSH 终端(没有图形会话环境)本脚本会自动补齐 X11 环境变量。

set -eu
cd "$(dirname "$0")"

if [ ! -x ./result/bin/clouddesktop-qml ]; then
  echo "result 链接不存在或不可执行: 请先在本目录执行 nix build 生成 result" >&2
  exit 1
fi

if [ -z "${DISPLAY:-}" ]; then
  export DISPLAY=:0
  for f in "/run/user/$(id -u)/gdm/Xauthority" \
           "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/.mutter-Xwaylandauth.*; do
    if [ -r "$f" ]; then
      export XAUTHORITY="$f"
      break
    fi
  done
  echo "当前终端无 DISPLAY,已补: DISPLAY=$DISPLAY XAUTHORITY=${XAUTHORITY:-<未找到,请手动 export>}"
fi

./result/bin/clouddesktop-qml &
echo "已后台拉起客户端(pid $!)。若客户端已在运行,新实例会提示 Another App is running 并自行退出(单实例行为,正常)。"
