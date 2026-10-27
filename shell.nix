# Classic-Nix dev shell (flakes are the primary interface; see flake.nix).
#   nix-shell -A shell
{ system ? builtins.currentSystem }:
let
  pkgs = import <nixpkgs> { inherit system; };
in
pkgs.mkShell {
  packages = with pkgs; [
    dpkg        # dpkg-deb for poking at the vendor deb
    binutils    # readelf/strings for binary analysis
    file
    systemd-catalog
    dbus
    make
    # the package itself, handy to poke at
    (pkgs.callPackage ./pkgs/ctyunclouddesk { })
  ];
}
