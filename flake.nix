{
  description = "NixOS configurations for orange and citrus-vm";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-hazkey = {
      url = "github:aster-void/nix-hazkey";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      agenix,
      home-manager,
      nixpkgs,
      ...
    }:
    let
      mkHost =
        {
          modules,
          specialArgs ? { },
          system,
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs;
          }
          // specialArgs;
          modules = [
            home-manager.nixosModules.home-manager
            ./modules/global/base.nix
            ./modules/global/pi.nix
          ]
          ++ modules;
        };
    in
    {
      nixosConfigurations.orange = mkHost {
        system = "x86_64-linux";
        specialArgs.orangeSettings = import ./hosts/orange/settings.nix;
        modules = [
          agenix.nixosModules.default
          ./hosts/orange/configuration.nix
        ];
      };

      nixosConfigurations.citrus-vm = mkHost {
        system = "x86_64-linux";
        modules = [
          ./hosts/citrus-vm/configuration.nix
        ];
      };

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;
    };
}
