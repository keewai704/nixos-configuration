{
  description = "NixOS configurations for citrus (desktop) and orange (server)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cpak = {
      url = "github:Containerpak/cpak/v2.14.6";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code = {
      url = "github:sadjow/claude-code-nix/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    t3code-releases = {
      url = "file+https://api.github.com/repos/pingdotgg/t3code/releases?per_page=100";
      flake = false;
    };

    meltype-release = {
      url = "file+https://api.github.com/repos/yksr-melt/Meltype/releases/latest";
      flake = false;
    };

    meltype-tags = {
      url = "file+https://api.github.com/repos/yksr-melt/Meltype/git/matching-refs/tags/";
      flake = false;
    };

    hyprland.url = "github:hyprwm/Hyprland/main";

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    proton-wineland-release = {
      url = "git+https://aur.archlinux.org/proton-wineland-bin.git?ref=master";
      flake = false;
    };

    millennium.url = "github:SteamClientHomebrew/Millennium?dir=packages/nix";

    nixcord.url = "github:4evy/nixcord";

    impasto = {
      url = "git+https://github.com/keewai704/impasto.git?ref=main";
      flake = false;
    };

    hypr-brightness = {
      url = "git+https://github.com/keewai704/hypr-brightness.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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

      packages.${system} = (pkgs.extend (import ./pkgs { inherit inputs; })).local;

      devShells.${system}.default = import ./devshell { inherit pkgs; };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
    };
}
