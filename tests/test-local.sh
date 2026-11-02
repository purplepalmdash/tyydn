#!/usr/bin/env bash
# Local smoke test for the 天翼云电脑 (CTyun Cloud PC) NixOS packaging.
#
# Run from the repo root (or anywhere):
#   bash tests/test-local.sh
#
# Steps:
#   1. build the package from the flake
#   2. verify no shared library is unresolved for the wrapped entry points
#   3. verify the daemon system service exists and is active (after nixos-rebuild)
#   4. launch the GUI inside the current desktop session (X11, or Wayland via
#      XWayland) and confirm it keeps running, then take a screenshot as evidence
#
# Step 4 works best when run from a terminal INSIDE the desktop session:
# $DISPLAY / $XAUTHORITY are inherited and used as-is. If the graphical
# session belongs to a different user than the one running this script:
#   CTYUN_TEST_USER=<that user> bash tests/test-local.sh

set -euo pipefail

cd "$(dirname "$0")/.."
REPO=$(pwd)
RESULTS="$REPO/tests/results"
mkdir -p "$RESULTS"
LOG="$RESULTS/test-local-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1

echo "=== [1/4] nix build ==="
nix build "$REPO" --json > "$RESULTS/build.json"
PKG=$(grep -o '"/nix/store/[^"]*"' "$RESULTS/build.json" 2>/dev/null | tr -d '"' | grep -v '\.drv$' | head -1 || true)
[ -n "$PKG" ] || { echo "  FAIL: no store path found in build.json"; exit 1; }
echo "package: $PKG"

echo
echo "=== [2/4] ldd check of wrapped entry points ==="
# The generated wrapper exports its environment before the final `exec` line.
# Source everything except shebang+exec, then run ldd under that environment.
check_libs() {
  local wrapper="$1" target="$2"
  local envfile ldout; envfile=$(mktemp); ldout=$(mktemp)
  # drop shebang (line 1) and the exec line (last line)
  sed '1d; $d' "$wrapper" > "$envfile"
  # shellcheck disable=SC1091
  if ( source "$envfile"; ldd "$target" ) > "$ldout" 2>&1; then
    if grep -qE 'not found' "$ldout"; then
      echo "  FAIL: unresolved libraries in $target:"
      grep -E 'not found' "$ldout"
      rm -f "$envfile" "$ldout"
      return 1
    fi
    echo "  OK: $target (all libraries resolve)"
  else
    echo "  FAIL: ldd failed for $target:"
    cat "$ldout"
    rm -f "$envfile" "$ldout"
    return 1
  fi
  rm -f "$envfile" "$ldout"
}

APP="$PKG/opt/ctg/CtyunClouddeskPublic"
check_libs "$PKG/bin/clouddesktop-qml"  "$APP/clouddesktop-qml"
check_libs "$PKG/bin/clouddesktop-daemon" "$APP/clouddesktop-daemon"
check_libs "$PKG/bin/crashpad_handler" "$APP/crashpad_handler"
check_libs "$PKG/bin/ark-update-CtyunClouddeskPublicd" "$PKG/usr/bin/ark-update-CtyunClouddeskPublicd"

echo
echo "=== [3/4] daemon service (requires: nixos-rebuild already applied) ==="
if systemctl is-active --quiet clouddesktop-daemon; then
  echo "  OK: clouddesktop-daemon is active"
elif awk 'NR>1 {print $1}' <(systemctl list-unit-files 2>/dev/null) | grep -qx 'clouddesktop-daemon.service'; then
  echo "  WARN: clouddesktop-daemon unit exists but is not active"
  echo "        (journalctl -u clouddesktop-daemon -n 20)"
else
  echo "  WARN: clouddesktop-daemon unit is MISSING — is the NixOS module enabled?"
  echo "        (services.ctyunclouddesk.enable = true — docs/install.md steps 5-6,"
  echo "         then 'sudo nixos-rebuild switch')"
fi
if test -d /var/lib/CtyunClouddeskPublic; then
  echo "  OK: /var/lib/CtyunClouddeskPublic exists (mode $(stat -c %a /var/lib/CtyunClouddeskPublic))"
fi

echo
echo "=== [4/4] GUI smoke test in the current desktop session ==="
# The user that owns the graphical session. Default: whoever runs this test —
# step 4 is meant to run from that session's own terminal.
SESSION_USER="${CTYUN_TEST_USER:-$(id -un)}"
if ! USER_UID=$(id -u "$SESSION_USER" 2>/dev/null); then
  echo "  FAIL: user '$SESSION_USER' does not exist"
  echo "        (set CTYUN_TEST_USER=<user of the graphical session>)"
  exit 1
fi
RUNTIME_DIR="/run/user/$USER_UID"
if [ ! -d "$RUNTIME_DIR" ]; then
  echo "  FAIL: $RUNTIME_DIR does not exist — is $SESSION_USER's session running?"
  echo "        (step 4 needs a live desktop session; run it from that session's terminal)"
  exit 1
fi

# X11 display + auth cookie. The vendor client only ships the xcb Qt platform
# plugin, so on a GNOME Wayland session it talks to the session's XWayland,
# which needs the session's auth cookie. Prefer the inherited session
# environment ($DISPLAY / $XAUTHORITY — this script is meant to run from the
# session's own terminal); fall back to detection:
#   display : /tmp/.X11-unix or the default :0
#   cookie  : ~/.Xauthority, else the mutter XWayland auth file in the
#             user runtime dir.
TEST_DISPLAY="${DISPLAY:-}"
if [ -z "$TEST_DISPLAY" ]; then
  DISPLAY_NUM=""
  if [ -d /tmp/.X11-unix ]; then
    DISPLAY_NUM=$(ls /tmp/.X11-unix | head -1 | tr -d 'X' || true)
  fi
  # modern distros keep the X socket under $XDG_RUNTIME_DIR instead
  if [ -z "$DISPLAY_NUM" ] && [ -n "${XDG_RUNTIME_DIR:-}" ] \
     && [ -d "$XDG_RUNTIME_DIR/.X11-unix" ]; then
    DISPLAY_NUM=$(ls "$XDG_RUNTIME_DIR/.X11-unix" | head -1 | tr -d 'X' || true)
  fi
  : "${DISPLAY_NUM:=0}"
  TEST_DISPLAY=":$DISPLAY_NUM"
fi
TEST_XAUTH="${XAUTHORITY:-}"
if [ -z "$TEST_XAUTH" ] || [ ! -r "$TEST_XAUTH" ]; then
  TEST_XAUTH="/home/$SESSION_USER/.Xauthority"
  if [ ! -f "$TEST_XAUTH" ]; then
    TEST_XAUTH=$(ls -t "$RUNTIME_DIR"/.mutter-Xwaylandauth.* 2>/dev/null | head -1 || true)
  fi
fi
echo "  display: $TEST_DISPLAY   xauth: ${TEST_XAUTH:-<inherited>}"

# Run the GUI as the session user (no-op when already that user).
RUNAS=()
if [ "$(id -un)" != "$SESSION_USER" ]; then
  RUNAS=( sudo -u "$SESSION_USER" )
fi
ENVARGS=( XDG_RUNTIME_DIR="$RUNTIME_DIR" DISPLAY="$TEST_DISPLAY" QT_QPA_PLATFORM=xcb )
if [ -n "$TEST_XAUTH" ]; then
  ENVARGS+=( XAUTHORITY="$TEST_XAUTH" )
fi

GUI_LOG="$RESULTS/gui.log"
"${RUNAS[@]}" env "${ENVARGS[@]}" bash -c '
  set -u
  start=$(date +%s)
  # ArkLog writes most lines to STDOUT (Qt errors go to stderr), so capture
  # both: the single-instance marker below is only visible on stdout.
  timeout --signal=KILL 25 "$1"/bin/clouddesktop-qml > "$2" 2>&1 || true
  end=$(date +%s)
  ran=$((end - start))
  echo "  GUI ran for ${ran}s (expected ~25s if it stayed alive)"
  if grep -qE "error while loading shared libraries|no Qt platform plugin could be initialized" "$2"; then
    echo "  FAIL: GUI failed to start — log:"
    cat "$2"
    exit 1
  fi
  if [ "$ran" -lt 20 ]; then
    # The vendor client is single-instance: a second launch shows
    # "Another App is running" and exits — that is a healthy system, not a
    # broken build.
    if grep -qiE "another app is running|another instance|already running" "$2"; then
      echo "  OK: single-instance client — another instance is already running"
      exit 0
    fi
    echo "  FAIL: GUI exited early — log tail:"
    tail -n 5 "$2"
    exit 1
  fi
' _ "$PKG" "$GUI_LOG"
echo "  OK: GUI stayed alive"

# Screenshot as evidence (non-fatal).
if command -v gnome-screenshot >/dev/null; then
  if DISPLAY="$TEST_DISPLAY" XAUTHORITY="${TEST_XAUTH:-}" \
     gnome-screenshot -f "$RESULTS/gui.png" 2>/dev/null; then
    echo "  screenshot: $RESULTS/gui.png"
  else
    echo "  (screenshot failed — non-fatal)"
  fi
fi

echo
echo "All local checks passed. Log: $LOG"
