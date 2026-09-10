{
  description = "supermemory-server: Nix package, overlay and NixOS service module";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      packageFor = system: (nixpkgs.legacyPackages.${system}.callPackage ./package.nix { });

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system: {
        default = packageFor system;
        supermemory-server = packageFor system;
      });

      legacyPackages = forAllSystems (system: {
        supermemory-server = packageFor system;
      });

      overlays.default = final: prev: {
        supermemory-server = final.callPackage ./package.nix { };
      };

      nixosModules.supermemory = import ./module.nix;
      nixosModules.default = import ./module.nix;
    };
}