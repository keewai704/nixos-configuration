{
  description = "NixOS configuration for orange";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agent-skills-nix = {
      url = "github:Kyure-A/agent-skills-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    hermes-agent.url = "github:NousResearch/hermes-agent/v2026.8.19";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      mcp-servers-nix,
      agent-skills-nix,
      hermes-agent,
      ...
    }:
    {
      nixosConfigurations.orange = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/orange/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;

              users.keewai =
                { pkgs, ... }:

                let
                  hermesHome = "/home/keewai/.hermes";
                  hermesPackage = hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
                in
                {
                  imports = [
                    mcp-servers-nix.homeManagerModules.default
                    agent-skills-nix.homeManagerModules.default
                    hermes-agent.homeManagerModules.default
                  ];

                  home = {
                    username = "keewai";
                    homeDirectory = "/home/keewai";
                    stateVersion = "26.05";
                    sessionVariables.CAMOFOX_URL = "http://127.0.0.1:9377";
                  };

                  # Keep the browser endpoint available to other user services.
                  systemd.user.sessionVariables.CAMOFOX_URL = "http://127.0.0.1:9377";

                  # Hermes configuration migrated from ~/.hermes/config.yaml.
                  # OAuth credentials remain in the private runtime auth.json;
                  # secrets must never be placed in settings or environment.
                  services.hermes-agent = {
                    enable = true;
                    package = hermesPackage;
                    installPackage = true;
                    hermesHome = hermesHome;
                    workingDirectory = "/home/keewai";

                    gateway.enable = true;
                    backend = {
                      mode = "dashboard";
                      host = "127.0.0.1";
                      port = 9119;
                      extraArgs = [ "--skip-build" ];
                    };

                    environment.CAMOFOX_URL = "http://127.0.0.1:9377";

                    settings = {
                      agent.max_turns = 150;
                      browser = {
                        cloud_provider = "camofox";
                        camofox.managed_persistence = false;
                      };
                      computer_use.backend = "cua";
                      display.tool_progress = "all";
                      image_gen = {
                        model = "gpt-image-2-high";
                        provider = "openai-codex";
                      };
                      model = {
                        base_url = "https://chatgpt.com/backend-api/codex";
                        default = "gpt-5.6-sol";
                        provider = "openai-codex";
                      };
                      platform_toolsets.cli = [
                        "bfl"
                        "browser"
                        "clarify"
                        "code_execution"
                        "computer_use"
                        "cronjob"
                        "delegation"
                        "file"
                        "image_gen"
                        "memory"
                        "session_search"
                        "skills"
                        "terminal"
                        "todo"
                        "tts"
                        "vision"
                        "web"
                      ];
                      session_reset.mode = "none";
                      web = {
                        backend = "parallel";
                        provider_tier.parallel = "free";
                      };
                    };
                  };

                  # MCP servers declared under `mcp-servers.programs` are shared
                  # with MCP-aware clients through Home Manager's registry.
                  programs.mcp.enable = true;
                  mcp-servers.programs.nixos = {
                    enable = true;
                    env = {
                      MCP_NIXOS_TRANSPORT = "stdio";
                      FASTMCP_CHECK_FOR_UPDATES = "off";
                      FASTMCP_SHOW_SERVER_BANNER = "false";
                      FASTMCP_ENV_FILE = "/dev/null";
                    };
                  };
                };
            };
          }
        ];
      };

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;
    };
}
