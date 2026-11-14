{
  description = "NixOS configurations for orange (server) and citrus (desktop)";

  nixConfig = {
    extra-substituters = [
      "https://cache.lantian.pub/lantian"
      "https://cache.nixos-cuda.org"
      "https://nix-community.cachix.org"
      "https://nyx-cache.chaotic.cx"
      "https://pi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      "lantian:WVGO7vsRMSEN+h7Lp7kv6SAmrkEXgUGbbXm7jMDjBuQ="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk="
      "pi.cachix.org-1:lGeoGJaZ5ZDabuRzkcD5EBTNnDM4HJ1vqeOxlWk1Flk="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    torne-driver = {
      url = "git+https://github.com/keewai704/torne_drv?ref=main";
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

    cachyos-limine-splash = {
      url = "file+https://raw.githubusercontent.com/CachyOS/cachyos-wallpapers/develop/usr/share/wallpapers/cachyos-wallpapers/limine-splash.png";
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

    amatsukaze-artifacts = {
      url = "file+https://api.github.com/repos/rigaya/Amatsukaze/actions/artifacts?per_page=100";
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

    pi = {
      url = "github:lukasl-dev/pi.nix/master";
    };

    pi-blackhole = {
      url = "git+https://github.com/k0valik/pi-blackhole?ref=main";
      flake = false;
    };

    t3code-nightly = {
      url = "git+https://aur.archlinux.org/t3code-nightly-bin.git?ref=master";
      flake = false;
    };

    mamba-ssm = {
      url = "git+https://github.com/state-spaces/mamba?ref=main";
      flake = false;
    };

    nemotronlabs-re-use = {
      url = "git+https://huggingface.co/nvidia/NVIDIA-NemotronLabs-RE-USE?ref=main";
      flake = false;
    };

    yomiyasu = {
      url = "git+https://github.com/nanaism/yomiyasu?ref=main";
      flake = false;
    };

    imozuru = {
      url = "git+https://github.com/MaryCache/imozuru?ref=main";
      flake = false;
    };

    impasto = {
      url = "git+https://github.com/andreumassanet/impasto?ref=main";
      flake = false;
    };

    stylix = {
      url = "github:nix-community/stylix/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plamo-app = {
      url = "git+https://github.com/keewai704/plamo-app?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    chaotic = {
      url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    };

    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel/release";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    nix-meltype = {
      url = "github:aster-void/nix-meltype/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixcord = {
      url = "github:4evy/nixcord/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    discord-system24 = {
      url = "github:refact0r/system24";
      flake = false;
    };

    millennium = {
      url = "github:SteamClientHomebrew/Millennium/main?dir=packages/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    millennium-theme-space = {
      url = "github:SpaceTheme/Steam";
      flake = false;
    };

    millennium-plugin-size-on-disk = {
      url = "tarball+https://steambrew.app/api/v1/plugins/download/?id=e73371b61eef68019413475b7642ecc37e53bbbd&n=size-on-disk.zip";
      flake = false;
    };

    millennium-plugin-hltb = {
      url = "tarball+https://steambrew.app/api/v1/plugins/download/?id=f685622bace6c63a70a24265f72fabd32aa497b5&n=hltb-for-millennium.zip";
      flake = false;
    };

    millennium-plugin-achievement-groups = {
      url = "tarball+https://steambrew.app/api/v1/plugins/download/?id=13f2dcc363c8afc41a42ba5df62aef06db1cc600&n=achievement-groups.zip";
      flake = false;
    };

    millennium-plugin-browser-history = {
      url = "tarball+https://steambrew.app/api/v1/plugins/download/?id=aca2451aea1d2bc5e5df9a2b8bb3d1b6a8f3fa8b&n=browser_history.zip";
      flake = false;
    };

    millennium-plugin-playercount-badge = {
      url = "tarball+https://steambrew.app/api/v1/plugins/download/?id=a8c27aa008d9a0b6d638ea6a9c6bceab30da78ef&n=playercount-badge.zip";
      flake = false;
    };

    millennium-plugin-protondb = {
      url = "tarball+https://steambrew.app/api/v1/plugins/download/?id=7913678dca9592b28d2f619aeefd47b06ebf36a2&n=protondb.zip";
      flake = false;
    };

    millennium-plugin-global-launch-options = {
      url = "tarball+https://steambrew.app/api/v1/plugins/download/?id=ade101371bfd58fb3de4c28d7f60b343325cc19d&n=global_launch_options.zip";
      flake = false;
    };

    millennium-plugin-proton-universal-prefix = {
      url = "tarball+https://steambrew.app/api/v1/plugins/download/?id=fce8d9cb1d31a1bae3715cbdfce4aa20511f92ec&n=proton_universal_prefix.zip";
      flake = false;
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
    in
    {
      nixosConfigurations.orange = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./modules/common
          ./hosts/orange
        ];
      };

      nixosConfigurations.citrus = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./modules/common
          ./hosts/citrus
        ];
      };

      nixosConfigurations.citrus-installer = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./modules/common
          ./hosts/citrus/installer
        ];
      };

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
