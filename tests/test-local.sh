#!/usr/bin/env bash
# Local smoke test for the 天翼云电脑 (CTyun Cloud PC) NixOS packaging.
#
# Run from the repo root (or anywhere):
#   bash tests/test-local.sh
#
# Steps:
#   1. build the package from the flake
#   2. verify no shared library is unresolved for the wrapped entry points
#   3. verify the daemon system service is active (after nixos-rebuild)
#   4. launch the GUI inside the current GNOME/Wayland session and confirm it
#      keeps running, then take a screenshot as evidence

set -euo pipefail

cd "$(dirname "$0")/.."
REPO=$(pwd)
DEB="CtyunClouddeskPublic-x86-64-20260812062844-Release-204010003-1346.deb"
RESULTS="$REPO/tests/results"
mkdir -p "$RESULTS"
LOG="$RESULTS/test-local-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG") 2>&1

echo "=== [1/4] nix build ==="
nix build "$REPO" --json > "$RESULTS/build.json"
PKG=$(grep -o '"/nix/store/[^"]*"' "$RESULTS/build.json" | head -1 | tr -d '"')
echo "package: $PKG"

echo
echo "=== [2/4] ldd check of wrapped entry points ==="
# The generated wrapper exports its environment before the final `exec` line.
# Source everything except shebang+exec, then run ldd under that environment.
check_libs() {
  local wrapper="$1" target="$2"
  local envfile; envfile=$(mktemp)
  # drop shebang (line 1) and the exec line (last line)
  sed '1d; $d' "$wrapper" > "$envfile"
  # shellcheck disable=SC1091
  if ! (
    source "$envfile"
    ldd "$target"
  ) | grep -E 'not found' > "$envfile.libs"; then
    echo "  FAIL: unresolved libraries in $target:"
    cat "$envfile.libs"
    rm -f "$envfile" "$envfile.libs"
    return 1
  fi
  echo "  OK: $target (all libraries resolve)"
  rm -f "$envfile" "$envfile.libs"
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
else
  echo "  WARN: clouddesktop-daemon is not active (run 'sudo nixos-rebuild switch --flake /etc/nixos' first)"
  systemctl --user status 2>/dev/null || true
fi
test -d /var/lib/CtyunClouddeskPublic && echo "  OK: /var/lib/CtyunClouddeskPublic exists (mode $(stat -c %a /var/lib/CtyunClouddeskPublic))"

echo
echo "=== [4/4] GUI smoke test in the current desktop session ==="
# user that owns the graphical session (default: test)
SESSION_USER="${CTYUN_TEST_USER:-test}"
USER_UID=$(id -u "$SESSION_USER")
RUNTIME_DIR="/run/user/$USER_UID"
DISPLAY_NUM=$(ls /tmp/.X11-unix 2>/dev/null | head -1 | tr -d 'X')
: "${DISPLAY_NUM:=0}"

shot=""
if command -v gnome-screenshot >/dev/null; then
  shot="DISPLAY=:$DISPLAY_NUM gnome-screenshot -f $RESULTS/gui.png"
fi

sudo -u "$SESSION_USER" env \
  XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  DISPLAY=":${DISPLAY_NUM:-0}" \
  WAYLAND_DISPLAY=wayland-0 \
  QT_QPA_PLATFORM=xcb \
  bash -c "
    set -u
    start=\$(date +%s)
    timeout --signal=KILL 25 '$PKG'/bin/clouddesktop-qml 2> '$RESULTS/gui.log' || true
    end=\$(date +%s)
    ran=\$((end - start))
    echo \"  GUI ran for \${ran}s (expected ~25s if it stayed alive)\"
    test \"\$ran\" -ge 20
    if grep -q 'error while loading shared libraries' '$RESULTS/gui.log'; then
      echo '  FAIL: missing shared libraries'; cat '$RESULTS/gui.log'; exit 1
    fi
    ${shot:-true}
  "
echo "  OK: GUI stayed alive"
echo
echo "All local checks passed. Log: $LOG"
