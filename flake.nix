{
  description = "NixOS configurations for orange and citrus";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    siora.url = "git+https://github.com/keewai704/siora.git?ref=main";

    agenix = {
      url = "github:ryantm/agenix";
      inputs.home-manager.follows = "home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland.url = "github:hyprwm/Hyprland/main";

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    millennium.url = "github:SteamClientHomebrew/Millennium?dir=packages/nix";

    my-firefox-nix.url = "git+https://github.com/keewai704/my-firefox-nix.git?ref=main";

    nix-hazkey = {
      url = "github:aster-void/nix-hazkey";
      inputs.home-manager.follows = "home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixcord.url = "github:4evy/nixcord";
  };

  outputs =
    inputs@{
      nixpkgs,
      ...
    }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      mkNixosHost =
        hostModules:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/common.nix
            ./modules/home-manager.nix
          ]
          ++ hostModules;
        };
    in
    {
      nixosConfigurations = {
        orange = mkNixosHost [
          inputs.agenix.nixosModules.default
          ./hosts/orange
        ];

        citrus = mkNixosHost [
          inputs.chaotic.nixosModules.default
          inputs.stylix.nixosModules.stylix
          ./hosts/citrus
        ];
      };

      packages.${system} = import ./pkgs { inherit pkgs; };

      devShells.${system}.default = import ./devshell { inherit pkgs; };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
    };
}
