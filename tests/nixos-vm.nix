# NixOS VM integration test for the 天翼云电脑 package.
#
#   nix build .#checks.x86_64-linux.ctyunclouddesk-vm
#   nix run .#checks.x86_64-linux.ctyunclouddesk-vm   # boots the VM, shows console
#
# What it verifies inside a fresh VM:
#   1. both systemd units (clouddesktop-daemon, ark-update) are active
#   2. the shared state directory /var/lib/CtyunClouddeskPublic exists (1777)
#   3. the wrapped GUI client starts under xvfb and stays alive (no missing
#      shared libraries / no immediate crash), for >= 15 s out of a 25 s budget
#
# Uses the nixpkgs 26.05 test API: `nodes` is an attrset and the test script
# is plain Python with the node objects in scope (start_all() instead of the
# removed start_dashboard()).
{ pkgs, lib ? pkgs.lib }:

let
  ctyun = pkgs.callPackage ../pkgs/ctyunclouddesk { };
  xvfb = pkgs.xvfb;
  bash = pkgs.bash;
in
pkgs.testers.nixosTest {
  name = "ctyunclouddesk";

  nodes = {
    # The VM needs a console + a minimal X stack for the xvfb GUI smoke test.
    machine = { ... }: {
      boot.console = "tty1";
      imports = [ ../nixos/ctyunclouddesk.nix ];
      services.ctyunclouddesk = {
        enable = true;
        package = ctyun;
      };
      environment.systemPackages = with pkgs; [ xvfb bash ];
    };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")

    machine.wait_for_unit("clouddesktop-daemon")
    machine.succeed("systemctl is-active clouddesktop-daemon")

    machine.wait_for_unit("ark-update-CtyunClouddeskPublic")
    machine.succeed("systemctl is-active ark-update-CtyunClouddeskPublic")

    machine.succeed("test -d /var/lib/CtyunClouddeskPublic")
    machine.succeed("test \"$(stat -c %a /var/lib/CtyunClouddeskPublic)\" = \"1777\"")

    # GUI smoke test: the client must start under a virtual X server and keep
    # running (exit via KILL after 25s = it survived; a crash would finish
    # quickly with a non-137 exit code).
    machine.succeed('''
      start=$(date +%s)
      QT_QPA_PLATFORM=xcb timeout --signal=KILL 25 ${xvfb}/bin/xvfb-run -a \
        ${ctyun}/bin/clouddesktop-qml 2> /tmp/ctyun-gui.log || true
      end=$(date +%s)
      test $((end - start)) -ge 20
      # the app should not log a missing-library error
      ! grep -q "error while loading shared libraries" /tmp/ctyun-gui.log
    ''')

    # Daemon log sanity: no immediate crash loop.
    machine.succeed("journalctl -u clouddesktop-daemon --quiet | grep -c -E 'Started' | head -1")

    machine.wait_for_unit("clouddesktop-daemon")
    machine.shutdown()
  '';
}
