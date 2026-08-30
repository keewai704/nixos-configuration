{
  description = "NixOS configurations for orange and citrus-vm";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.home-manager.follows = "home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-hazkey = {
      url = "github:aster-void/nix-hazkey";
      inputs.home-manager.follows = "home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      ...
    }:
    let
      system = "x86_64-linux";

      packagePkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = package: nixpkgs.lib.getName package == "chatgpt-desktop";
      };
      localPackages = {
        camofox-browser = packagePkgs.callPackage ./pkgs/camofox {
          websockify = packagePkgs.python3Packages.websockify;
        };
        chatgpt-desktop = packagePkgs.callPackage ./pkgs/chatgpt-desktop { };
        cua-driver = packagePkgs.callPackage ./pkgs/cua-driver { };
      };

      mkHost =
        modules:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/common.nix
          ]
          ++ modules;
        };
    in
    {
      nixosConfigurations.orange = mkHost [
        inputs.agenix.nixosModules.default
        ./hosts/orange/configuration.nix
      ];

      nixosConfigurations.citrus-vm = mkHost [
        inputs.stylix.nixosModules.stylix
        ./hosts/citrus-vm/configuration.nix
      ];

      packages.${system} = localPackages;

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
    };
}
