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
  desktopFile = "${cfg.package}/usr/share/applications/CtyunClouddeskPublic.desktop";

  # Per-user oneshot services that install the autostart entry, mirroring the
  # vendor postinst behaviour of copying the .desktop file into
  # ~/.config/autostart of every existing user.
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
        ExecStart = "${pkgs.bash}/bin/bash -c " + ''
          set -e
          mkdir -p "/home/${user}/.config/autostart"
          install -m 755 ${desktopFile} "/home/${user}/.config/autostart/CtyunClouddeskPublic.desktop"'
        '';
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
        ExecStart = "${pkgs.bash}/bin/bash -c " + ''
          set -e
          dest=""
          [ -d "/home/${user}/桌面" ] && dest="/home/${user}/桌面"
          [ -z "$dest" ] && [ -d "/home/${user}/Desktop" ] && dest="/home/${user}/Desktop"
          [ -n "$dest" ] || { echo "no desktop dir for ${user}, skipping"; exit 0; }
          install -m 755 ${desktopFile} "$dest/CtyunClouddeskPublic.desktop"
          "${pkgs.gnome.gio}/bin/gio" set "$dest/CtyunClouddeskPublic.desktop" metadata::trusted true 2>/dev/null || true'
        '';
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
  };

  config = mkIf cfg.enable {

    # /opt/ctg/..., /usr/bin/ark-update-*, /usr/share/applications/...
    system.path = [ cfg.package ];

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
    } // autostartServices // desktopShortcutServices;

    # Vendor USB permission rule (postinst set_usb_permission):
    #   SUBSYSTEM=="usb", MODE="0666", GROUP="dialout"
    # (option moved from hardware.udev to services.udev in nixpkgs >= 26.05)
    services.udev.extraRules = optionals cfg.usbPermission.enable [
      ''
        SUBSYSTEM=="usb", MODE="0666", GROUP="dialout"
      ''
    ];

    users.users = usbUsers;

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
    ];
  };
}
