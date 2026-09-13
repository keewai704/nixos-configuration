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

      packagePkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = package: nixpkgs.lib.getName package == "chatgpt-desktop";
      };
      localPackages = {
        apple-music-client = packagePkgs.callPackage ./pkgs/apple-music-client {
          src = inputs.apple-music-client;
          authService = inputs.apple-music-client.packages.${system}.auth-service;
        };
        chatgpt-desktop = packagePkgs.callPackage ./pkgs/chatgpt-desktop { };
        cua-driver = packagePkgs.callPackage ./pkgs/cua-driver { };
        # Preserve the upstream Steam package's override interface.
        millennium-steam = import ./pkgs/millennium-steam {
          inherit (packagePkgs) lib stdenv;
          inherit (inputs) millennium;
        };
      };

      mkHost =
        modules:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/common.nix
            ./modules/home-manager.nix
          ]
          ++ modules;
        };
    in
    {
      nixosConfigurations.orange = mkHost [
        inputs.agenix.nixosModules.default
        ./hosts/orange
      ];

      nixosConfigurations.citrus = mkHost [
        inputs.chaotic.nixosModules.default
        inputs.stylix.nixosModules.stylix
        ./hosts/citrus
      ];

      nixosConfigurations.citrus-vm = mkHost [
        inputs.chaotic.nixosModules.default
        inputs.stylix.nixosModules.stylix
        ./hosts/citrus-vm
      ];

      packages.${system} = localPackages;

      checks.${system} = {
        citrus-vm = import ./checks/citrus-vm.nix {
          inherit (nixpkgs) lib;
          pkgs = packagePkgs;
          config = inputs.self.nixosConfigurations.citrus-vm.config;
        };

        orange-health-monitor =
          inputs.self.nixosConfigurations.orange.config.system.build.orangeHealthMonitorCheck;

        package-ownership = import ./checks/package-ownership.nix {
          inherit (nixpkgs) lib;
          pkgs = packagePkgs;
          citrus = inputs.self.nixosConfigurations.citrus.config;
          orange = inputs.self.nixosConfigurations.orange.config;
        };

      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
    };
}
