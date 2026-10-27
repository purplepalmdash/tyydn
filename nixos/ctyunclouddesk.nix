{ config, lib, pkgs, ... }:

# NixOS module for 天翼云电脑 (CTyun Cloud PC / "AI 云电脑").
#
# Replicates what the vendor's deb maintainer scripts (postinst) do, in a
# declarative NixOS way:
#   * expose the payload on the system path (/opt/ctg, /usr/share/applications)
#   * create the shared state dir /var/lib/CtyunClouddeskPublic (mode 1777)
#   * run clouddesktop-daemon as a system service
#   * run the ark-update self-update daemon as a system service (optional)
#   * optionally install per-user autostart entries and desktop shortcuts
#   * optionally apply the vendor's USB permission udev rule
#
# See docs/deb-analysis.md for the analysis of the original postinst.

with lib;

let
  cfg = config.services.ctyunclouddesk;
  desktopFile = "${cfg.package}/share/applications/CtyunClouddeskPublic.desktop";

  # Per-user oneshot services that install the autostart entry, mirroring the
  # vendor postinst behaviour of copying the .desktop file into
  # ~/.config/autostart of every existing user.
  #
  # The installer is a real script (writeShellScriptBin), not an inline
  # multi-line `bash -c`: systemd's ExecStart is a single line, and NixOS
  # would emit the raw newlines, which systemd parses as extra directives
  # (a line starting with '[' is even taken for a section header, yielding
  # "Unit failed to load properly: Bad message").
  autostartServices = listToAttrs (map (user: {
    name = "ctyunclouddesk-autostart-${user}";
    value = {
      description = "Install 天翼云电脑 autostart entry for user ${user}";
      after = [ "users.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = user;
        RemainAfterExit = true;
        ExecStart = "${pkgs.writeShellScriptBin "ctyunclouddesk-autostart-${user}" ''
          set -e
          mkdir -p "/home/${user}/.config/autostart"
          install -m 755 ${desktopFile} "/home/${user}/.config/autostart/CtyunClouddeskPublic.desktop"
        ''}/bin/ctyunclouddesk-autostart-${user}";
      };
    };
  }) cfg.autostartUsers);

  # Per-user desktop shortcuts (vendor postinst also copies the .desktop
  # file onto the desktop).
  desktopShortcutServices = listToAttrs (map (user: {
    name = "ctyunclouddesk-desktop-shortcut-${user}";
    value = {
      description = "Install 天翼云电脑 desktop shortcut for user ${user}";
      after = [ "users.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = user;
        RemainAfterExit = true;
        ExecStart = "${pkgs.writeShellScriptBin "ctyunclouddesk-desktop-shortcut-${user}" ''
          set -e
          dest=""
          [ -d "/home/${user}/桌面" ] && dest="/home/${user}/桌面"
          [ -z "$dest" ] && [ -d "/home/${user}/Desktop" ] && dest="/home/${user}/Desktop"
          [ -n "$dest" ] || { echo "no desktop dir for ${user}, skipping"; exit 0; }
          install -m 755 ${desktopFile} "$dest/CtyunClouddeskPublic.desktop"
          "${pkgs.glib.bin}/bin/gio" set "$dest/CtyunClouddeskPublic.desktop" metadata::trusted true 2>/dev/null || true
        ''}/bin/ctyunclouddesk-desktop-shortcut-${user}";
      };
    };
  }) cfg.desktopShortcutUsers);

  # USB redirection: add the listed users to the dialout group.
  usbUsers = listToAttrs (map (user: {
    name = user;
    value = {
      extraGroups = mkMerge [ [ "dialout" ] ];
    };
  }) cfg.usbPermission.users);

  # Xfce WM keyboard-shortcut repair (autostart entry).
  #
  # Xfce 4.20 WM shortcuts come from the xfconf channel
  # "xfce4-keyboard-shortcuts": /xfwm4/default/* (defined by the
  # libxfce4ui package's perchannel XML) is cloned into /xfwm4/custom/*
  # on the FIRST session, with /xfwm4/custom/override=true set. If that
  # first session ran before the default definitions were visible in
  # XDG_CONFIG_DIRS, the clone is empty and xfwm4 has NO shortcuts at
  # all (Alt+Tab/Alt+F4/Alt+F11 dead), and the provider never re-clones
  # (override=true). This script mirrors /xfwm4/default/* into
  # /xfwm4/custom/* once; xfwm4 re-grabs the keys live.
  xfceShortcutRepair = pkgs.writeShellScriptBin "ctyunclouddesk-xfce-shortcuts-repair" ''
    set -u
    # Only inside a graphical Xfce session (the channel is Xfce-specific).
    [ "''${DESKTOP_SESSION:-}" = "xfce" ] || exit 0
    XQ=${pkgs.xfconf}/bin/xfconf-query
    if [ -z "''${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
      DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
      export DBUS_SESSION_BUS_ADDRESS
    fi
    # Fast path: custom bindings already populated (the 'override' marker
    # does not count as a binding).
    n=$("$XQ" -c xfce4-keyboard-shortcuts -p /xfwm4/custom -l 2>/dev/null \
          | grep -E '^/xfwm4/custom/[^/]+$' \
          | grep -cv '^/xfwm4/custom/override$' || true)
    [ "''${n:-0}" -gt 0 ] && exit 0
    # Nothing to mirror if the defaults are not visible either.
    defaults=$("$XQ" -c xfce4-keyboard-shortcuts -p /xfwm4/default -l 2>/dev/null \
          | grep -E '^/xfwm4/default/[^/]+$' || true)
    [ -n "$defaults" ] || exit 0
    while read -r p; do
      [ -n "$p" ] || continue
      name=''${p#/xfwm4/default/}
      v=$("$XQ" -c xfce4-keyboard-shortcuts -p "$p")
      if [ -n "$v" ]; then
        "$XQ" -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/$name" -s "$v" -t string --create || true
      fi
    done <<DEFAULTS
    $defaults
    DEFAULTS
  '';

  # Per-user oneshot services that install the repair autostart entry.
  xfceShortcutRepairServices = listToAttrs (map (user: {
    name = "ctyunclouddesk-xfce-shortcuts-${user}";
    value = {
      description = "Install Xfce WM shortcut repair autostart entry for user ${user}";
      after = [ "users.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = user;
        RemainAfterExit = true;
        ExecStart = "${pkgs.writeShellScriptBin "ctyunclouddesk-xfce-shortcuts-${user}" ''
          set -e
          mkdir -p "/home/${user}/.config/autostart"
          cat > "/home/${user}/.config/autostart/ctyunclouddesk-xfce-shortcuts-fix.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=CTyun Xfce WM shortcut repair
Exec=${xfceShortcutRepair}/bin/ctyunclouddesk-xfce-shortcuts-repair
X-GNOME-Autostart-Phase=Initialization
EOF
        ''}/bin/ctyunclouddesk-xfce-shortcuts-${user}";
      };
    };
  }) cfg.xfceSession.repairUsers);

  # Xfce perchannel XML definitions that nixpkgs does not add to
  # XDG_CONFIG_DIRS itself (libxfce4util's resource lookup searches
  # XDG_CONFIG_DIRS + /etc/xdg for <dir>/xfce4/xfconf/...):
  #   xfce4-session: xfce4-session.xml = failsafe session definition;
  #                  missing -> "Unable to load a failsafe session"
  #   libxfce4ui:    xfce4-keyboard-shortcuts.xml = xfwm4 default WM
  #                  shortcuts; missing/stale -> no Alt+Tab/Alt+F4/Alt+F11
  # The list form of environment.sessionVariables is merged with the
  # system's standard XDG suffixes (see nixos/modules/config/
  # system-environment.nix), so user definitions are not clobbered.
  xfceConfigDirs = map (p: "${p}/etc/xdg") ((with pkgs.xfce; [
    xfce4-session xfce4-settings xfce4-panel xfce4-notifyd thunar garcon
  ]) ++ [ pkgs.libxfce4ui ]);

  # All per-user / per-group option lists must reference real users.
  existingUsers = config.users.users;
  assertUsers = users:
    users
    == (filter (u: existingUsers ? ${u}) users);
in
{
  options.services.ctyunclouddesk = {
    enable = mkEnableOption "the 天翼云电脑 (CTyun Cloud PC) desktop client";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../pkgs/ctyunclouddesk { };
      description = "Package containing the client payload and wrapped entry points.";
    };

    enableDaemon = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Run the clouddesktop-daemon service (required by the client;
        it maintains the shared state directory /var/lib/CtyunClouddeskPublic).
      '';
    };

    enableUpdater = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Run the vendor self-update daemon (ark-update-CtyunClouddeskPublicd).
        It periodically checks for newer client versions. Disable it when you
        want to control updates manually (note: store paths are read-only, so
        a self-update that writes into the payload directory only affects the
        running system until the next nixos-rebuild).
      '';
    };

    autostartUsers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        User accounts for which the client is added to
        ~/.config/autostart (mirrors the vendor postinst behaviour).
      '';
    };

    desktopShortcutUsers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        User accounts for which a desktop shortcut is placed on the desktop
        directory (~/Desktop or ~/桌面), mirroring the vendor postinst.
      '';
    };

    usbPermission = mkOption {
      type = types.submodule {
        options.enable = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Install the vendor udev rule that makes USB devices writable by
            the "dialout" group (needed for USB device redirection).
            This is what the vendor postinst writes to /etc/udev/rules.d.
          '';
        };
        options.users = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "User accounts to add to the dialout group.";
        };
      };
      default = { enable = true; users = [ ]; };
      description = "USB redirection permission settings (vendor udev rule + dialout group).";
    };

    xfceSession = mkOption {
      type = types.submodule {
        options.enable = mkEnableOption ''
          an Xorg + Xfce desktop session with working window-manager keyboard
          shortcuts (Alt+Tab, Alt+F4, Alt+F11, ...). The client is a pure
          X11/xcb application; this is the native-X11 desktop setup it was
          validated on. GNOME/Wayland sessions keep working via XWayland.
        '';
        options.videoDrivers = mkOption {
          type = types.listOf types.str;
          default = [ "modesetting" ];
          description = ''
            Xorg video driver(s). "modesetting" works with the QEMU/virtio
            GPU (and most KVM virtio-gpu and many bare-metal GPUs); use
            "intel"/"nvidia"/"amdgpu" for dedicated hardware.
          '';
        };
        options.defaultSession = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Set services.displayManager.defaultSession = "xfce" (marked as
            mkDefault, so an explicit user value wins). Autologin then goes
            to Xfce/Xorg; all other sessions stay selectable in the GDM
            session chooser.
          '';
        };
        options.repairUsers = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            User accounts whose Xfce session may already have a stale or
            empty xfwm4 keybinding channel (empty /xfwm4/custom plus
            override=true, frozen by the shortcut provider's first run
            before the default definitions were visible). For each user an
            autostart entry runs a small repair script that mirrors
            /xfwm4/default/* into /xfwm4/custom/* once. Fresh users (no
            previous Xfce session) don't need this.
          '';
        };
      };
      default = {
        enable = false;
        videoDrivers = [ "modesetting" ];
        defaultSession = true;
        repairUsers = [ ];
      };
      description = ''
        Xorg + Xfce session for the pure-X11 client, including the
        XDG_CONFIG_DIRS entries that carry Xfce's perchannel definitions
        (failsafe session + default WM shortcuts) and an optional
        per-user repair for stale xfwm4 keybinding channels.
      '';
    };
  };

  config = mkIf cfg.enable {

    # /opt/ctg/..., /usr/bin/ark-update-*, /usr/share/applications/...
    # (the system profile is what /run/current-system/sw links to)
    environment.systemPackages = [ cfg.package ];

    # Shared state dir between daemon and clients (vendor: mkdir 1777).
    systemd.tmpfiles.rules = [
      "d /var/lib/CtyunClouddeskPublic 1777 root root -"
    ];

    systemd.services = {
      clouddesktop-daemon = optionalAttrs cfg.enableDaemon {
        description = "天翼云电脑 client daemon";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        environment = {
          XDG_DATA_HOME = "/var/lib/CtyunClouddeskPublic";
        };
        script = ''
          exec ${cfg.package}/bin/clouddesktop-daemon -e
        '';
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = 5;
        };
      };

      # Vendor unit name kept for drop-in compatibility.
      ark-update-CtyunClouddeskPublic = optionalAttrs cfg.enableUpdater {
        description = "天翼云电脑 self-update daemon (ark-update)";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "forking";
          ExecStart = "${cfg.package}/bin/ark-update-CtyunClouddeskPublicd";
          Restart = "always";
          KillMode = "process";
        };
      };
    } // autostartServices // desktopShortcutServices // xfceShortcutRepairServices;

    # Vendor USB permission rule (postinst set_usb_permission):
    #   SUBSYSTEM=="usb", MODE="0666", GROUP="dialout"
    # (option moved from hardware.udev to services.udev in nixpkgs >= 26.05)
    services.udev.extraRules = optionalString cfg.usbPermission.enable ''
      SUBSYSTEM=="usb", MODE="0666", GROUP="dialout"
    '';

    users.users = usbUsers;

    # Xorg + Xfce session with working WM shortcuts (see xfceSession).
    services.xserver = mkIf cfg.xfceSession.enable {
      enable = true;
      videoDrivers = cfg.xfceSession.videoDrivers;
      desktopManager.xfce.enable = true;
    };
    services.displayManager.defaultSession = mkIf cfg.xfceSession.enable (
      mkDefault (optionalString cfg.xfceSession.defaultSession "xfce")
    );
    environment.sessionVariables.XDG_CONFIG_DIRS =
      mkIf cfg.xfceSession.enable xfceConfigDirs;

    assertions = [
      {
        assertion = assertUsers cfg.autostartUsers;
        message = "services.ctyunclouddesk.autostartUsers: all users must exist in users.users (${concatStringsSep ", " cfg.autostartUsers})";
      }
      {
        assertion = assertUsers cfg.desktopShortcutUsers;
        message = "services.ctyunclouddesk.desktopShortcutUsers: all users must exist in users.users (${concatStringsSep ", " cfg.desktopShortcutUsers})";
      }
      {
        assertion = assertUsers cfg.usbPermission.users;
        message = "services.ctyunclouddesk.usbPermission.users: all users must exist in users.users (${concatStringsSep ", " cfg.usbPermission.users})";
      }
      {
        assertion = assertUsers cfg.xfceSession.repairUsers;
        message = "services.ctyunclouddesk.xfceSession.repairUsers: all users must exist in users.users (${concatStringsSep ", " cfg.xfceSession.repairUsers})";
      }
    ];
  };
}
