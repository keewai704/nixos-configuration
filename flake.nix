{
  description = "NixOS configurations for citrus (desktop) and orange (server)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";

    claude-code = {
      url = "github:sadjow/claude-code-nix/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    codex-cli = {
      url = "github:sadjow/codex-cli-nix/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    t3code-release = {
      url = "file+https://github.com/pingdotgg/t3code/releases/latest/download/latest-linux.yml";
      flake = false;
    };

    hyprland.url = "github:hyprwm/Hyprland/main";

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    millennium.url = "github:SteamClientHomebrew/Millennium?dir=packages/nix";

    nix-hazkey = {
      url = "github:aster-void/nix-hazkey";
      inputs.home-manager.follows = "home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixcord.url = "github:4evy/nixcord";

    hypr-island = {
      url = "git+https://github.com/keewai704/hypr-island.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hypr-brightness = {
      url = "git+https://github.com/keewai704/hypr-brightness.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    siora.url = "git+https://github.com/keewai704/siora.git?ref=main";
  };

  outputs =
    inputs@{ nixpkgs, ... }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      mkHost =
        name:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/common
            ./hosts/${name}
          ];
        };
    in
    {
      nixosConfigurations = nixpkgs.lib.genAttrs [ "citrus" "orange" ] mkHost;

      packages.${system} = import ./pkgs { inherit pkgs; };

      devShells.${system}.default = import ./devshell { inherit pkgs; };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
    };
}
