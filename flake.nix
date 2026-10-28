{
  description = "Monitoring-ready sysadmin checks: TLS expiry, disk/inodes, SSH keys, restic backups";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.callPackage ./nix/package.nix { };
      });

      nixosModules.default = import ./nix/module.nix self;

      checks = forAllSystems (pkgs: {
        lint = pkgs.runCommand "ops-toolkit-lint" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
          cd ${self}
          shellcheck -x bin/* lib/*.sh
          touch $out
        '';
        bats =
          pkgs.runCommand "ops-toolkit-bats"
            {
              nativeBuildInputs = with pkgs; [
                bats
                openssl
                jq
              ];
            }
            ''
              cp -r ${self} src && chmod -R u+w src
              patchShebangs src
              bats src/tests
              touch $out
            '';
        module = import ./nix/test.nix { inherit pkgs self; };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            bats
            shellcheck
            shfmt
            openssl
            jq
            restic
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
