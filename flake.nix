{
  description = "NixOS configurations for citrus (desktop) and orange (server)";

  nixConfig = {
    extra-substituters = [
      "https://claude-code.cachix.org"
      "https://codex-cli.cachix.org"
      "https://umbriel.cachix.org"
      "https://noctalia.cachix.org"
      "https://nix-community.cachix.org"
      "https://cache.flox.dev?priority=50"
      "https://cache.nixos-cuda.org"
      "https://cache.xinux.uz"
    ];
    extra-trusted-public-keys = [
      "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      "codex-cli.cachix.org-1:1Br3H1hHoRYG22n//cGKJOk3cQXgYobUel6O8DgSing="
      "umbriel.cachix.org-1:JfNq/2yg2S6D6z4Z2dVSZrZlDPQTKtexB6GAVLD98nw="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      "cache.xinux.uz:BXCrtqejFjWzWEB9YuGB7X2MV4ttBur1N8BkwQRdH+0="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    coax = {
      url = "git+https://github.com/Till0196/coax?ref=main";
      flake = false;
    };

    bondriver-coax = {
      url = "git+https://github.com/Till0196/BonDriver_coax?ref=main";
      flake = false;
    };

    coax-rs = {
      url = "git+https://github.com/Till0196/coax-rs?ref=main";
      flake = false;
    };

    b25-decoder = {
      url = "git+https://github.com/tsukumijima/Multi2Dec?ref=master";
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
      url = "file+https://github.com/tsukumijima/KonomiTV/releases/latest/download/thirdparty-linux.tar.xz";
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

    deepseek-harness-release = {
      url = "file+https://registry.npmjs.org/@deepseek-ai/dsh/next";
      flake = false;
    };

    dsh-claude-bridge-release = {
      url = "file+https://registry.npmjs.org/dsh-claude-bridge/latest";
      flake = false;
    };

    dsh-codex-native-releases = {
      url = "file+https://api.github.com/repos/Tests4gptplay/dsh-codex-native/releases?per_page=20";
      flake = false;
    };

    claude-agent-sdk-release = {
      url = "file+https://registry.npmjs.org/@anthropic-ai/claude-agent-sdk/latest";
      flake = false;
    };

    dsh-mobile-maxxing = {
      url = "github:kuraneko1/dsh-mobile-maxxing/main";
      flake = false;
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

    umbriel.url = "github:noctalia-dev/umbriel/cachix";

    noctalia.url = "github:noctalia-dev/noctalia/cachix";

    noctalia-templates = {
      url = "github:noctalia-dev/community-templates";
      flake = false;
    };

    owly = {
      url = "git+https://github.com/t4t5/owly?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/master";

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
      nixosConfigurations = nixpkgs.lib.genAttrs [ "citrus" "orange" ] mkHost;

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
