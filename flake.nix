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
      agenix,
      nixpkgs,
      ...
    }:
    let
      chatgptPkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfreePredicate = package: nixpkgs.lib.getName package == "chatgpt-desktop";
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
        agenix.nixosModules.default
        ./hosts/orange/configuration.nix
      ];

      nixosConfigurations.citrus-vm = mkHost [
        inputs.stylix.nixosModules.stylix
        ./hosts/citrus-vm/configuration.nix
      ];

      packages.x86_64-linux.chatgpt-desktop = chatgptPkgs.callPackage ./pkgs/chatgpt-desktop { };

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;
    };
}
