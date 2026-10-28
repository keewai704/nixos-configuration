{
  description = "NixOS configuration for orange (server)";

  nixConfig = {
    extra-substituters = [
      "https://claude-code.cachix.org"
      "https://codex-cli.cachix.org"
      "https://nix-community.cachix.org"
      "https://cache.nixos-cuda.org"
    ];
    extra-trusted-public-keys = [
      "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      "codex-cli.cachix.org-1:1Br3H1hHoRYG22n//cGKJOk3cQXgYobUel6O8DgSing="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    torne-driver = {
      url = "git+https://github.com/mihalinn/torne_drv?ref=main";
      flake = false;
    };

    mirakc = {
      url = "git+https://github.com/mirakc/mirakc?ref=release";
      flake = false;
    };

    mirakc-arib = {
      url = "git+https://github.com/mirakc/mirakc-arib?ref=main&submodules=1";
      flake = false;
    };

    mirakc-swagger-ui = {
      url = "file+https://github.com/swagger-api/swagger-ui/archive/refs/heads/master.zip";
      flake = false;
    };

    bondriver-linuxmirakc = {
      url = "git+https://github.com/matching/BonDriver_LinuxMirakc?ref=main&submodules=1";
      flake = false;
    };

    b25-decoder = {
      url = "git+https://github.com/tsukumijima/Multi2Dec?ref=master";
      flake = false;
    };

    tsreplace = {
      url = "git+https://github.com/rigaya/tsreplace?ref=master";
      flake = false;
    };

    pyproject-nix = {
      url = "git+https://github.com/pyproject-nix/pyproject.nix?ref=master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "git+https://github.com/pyproject-nix/uv2nix?ref=master";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "git+https://github.com/pyproject-nix/build-system-pkgs?ref=master";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    edcb = {
      url = "git+https://github.com/xtne6f/EDCB?ref=work-plus-s";
      flake = false;
    };

    konomitv-thirdparty = {
      url = "file+https://nightly.link/tsukumijima/KonomiTV/workflows/build_thirdparty.yaml/master/thirdparty-linux.tar.xz.zip";
      flake = false;
    };

    konomitv = {
      url = "git+https://github.com/tsukumijima/KonomiTV?ref=master";
      flake = false;
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
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

    codex = {
      url = "github:sadjow/codex-cli-nix/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    t3code-releases = {
      url = "file+https://api.github.com/repos/pingdotgg/t3code/releases?per_page=100";
      flake = false;
    };

    iphone-control = {
      url = "git+https://github.com/keewai704/iphone-control?ref=main";
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
      nixosConfigurations = nixpkgs.lib.genAttrs [ "orange" ] mkHost;

      packages.${system} = (pkgs.extend (import ./pkgs { inherit inputs; })).local;

      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          nixd
          nixfmt
          statix
          deadnix
          lua-language-server
          stylua
          bash-language-server
          shellcheck
          shfmt
        ];
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
    };
}
