{
  description = "NixOS configurations for orange, citrus, and citrus-vm";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    apple-music-client.url = "git+https://github.com/keewai704/apple-music-client.git?ref=main";

    dynamic-island = {
      url = "git+https://github.com/keewai704/hypr-island.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

    codex-cli-nix = {
      url = "github:sadjow/codex-cli-nix/main";
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
        config.allowUnfreePredicate = package: nixpkgs.lib.getName package == "chatgpt-desktop";
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

        citrus-vm = mkNixosHost [
          inputs.chaotic.nixosModules.default
          inputs.stylix.nixosModules.stylix
          ./hosts/citrus-vm
        ];
      };

      packages.${system} = import ./pkgs { inherit inputs pkgs; };

      devShells.${system}.default = import ./devshell { inherit pkgs; };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
    };
}
