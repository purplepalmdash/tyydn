{
  description = "NixOS packaging for 天翼云电脑 (CTyun Cloud PC / AI 云电脑)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      packageSet = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          ctyunclouddeskpublic = pkgs.callPackage ./pkgs/ctyunclouddesk { };
          default = self.packages.${system}.ctyunclouddeskpublic;
        };
    in
    {
      packages = nixpkgs.lib.genAttrs systems packageSet;

      nixosModules.ctyunclouddesk = import ./nixos/ctyunclouddesk.nix;

      # Example NixOS configuration that boots a minimal system with the
      # client enabled; useful as a template and for the VM test.
      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          {
            networking.hostName = "ctyun-test";
            networking.networkmanager.enable = true;
            imports = [ ./nixos/ctyunclouddesk.nix ];
            services.ctyunclouddesk = {
              enable = true;
              # 原生 X11 桌面(Xorg + Xfce)+ WM 快捷键(见 docs/guide.md 第 7 步):
              # xfceSession.enable = true;
            };
          }
        ];
      };

      devShells = nixpkgs.lib.genAttrs systems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              dpkg        # dpkg-deb for poking at the vendor deb
              binutils    # readelf/strings for binary analysis
              file
              systemd-catalog
              dbus
              make
            ];
          };
        }
      );

      # Heavy: builds a VM image. Run with:
      #   nix build .#checks.x86_64-linux.ctyunclouddesk-vm
      checks = nixpkgs.lib.genAttrs systems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          ctyunclouddesk-vm = import ./tests/nixos-vm.nix {
            inherit (nixpkgs) lib;
            inherit pkgs;
          };
        }
      );
    };
}
