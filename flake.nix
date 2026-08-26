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

  };

  outputs =
    {
      nixpkgs,
      home-manager,
      mcp-servers-nix,
      agent-skills-nix,
      ...
    }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.orange = nixpkgs.lib.nixosSystem {
        inherit system;
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
                  ponytailMcp = pkgs.callPackage ./pkgs/ponytail-mcp/package.nix { };
                in
                {
                  imports = [
                    mcp-servers-nix.homeManagerModules.default
                    agent-skills-nix.homeManagerModules.default
                  ];

                  home = {
                    username = "keewai";
                    homeDirectory = "/home/keewai";
                    stateVersion = "26.05";
                    sessionVariables.CAMOFOX_URL = "http://127.0.0.1:9377";
                  };

                  # Keep the browser endpoint available to user services.
                  systemd.user.sessionVariables.CAMOFOX_URL = "http://127.0.0.1:9377";

                  # MCP servers declared under `mcp-servers.programs` are shared
                  # with MCP-aware clients through Home Manager's registry.
                  programs.mcp.enable = true;

                  # Codex has no native LSP client. Give it semantic code tools
                  # through Serena's MCP server while retaining the separately
                  # pinned Codex CLI package in the user's Nix profile.
                  programs.codex = {
                    enable = true;
                    package = null;
                    enableMcpIntegration = true;

                    # Preserve the existing user-level Codex configuration when
                    # Home Manager takes ownership of config.toml.
                    settings = {
                      model = "gpt-5.6-sol";
                      model_reasoning_effort = "max";
                      service_tier = "priority";
                      approval_policy = "never";
                      approvals_reviewer = "user";
                      sandbox_mode = "danger-full-access";

                      marketplaces.openai-bundled = {
                        source_type = "local";
                        source = "/home/keewai/.codex/.tmp/bundled-marketplaces/openai-bundled";
                      };

                      plugins = {
                        "sites@openai-bundled".enabled = true;
                        "visualize@openai-bundled".enabled = true;
                      };

                      projects."/home/keewai/nixos-configuration".trust_level = "trusted";
                    };
                  };

                  # The current config is an unmanaged regular file. Replace it
                  # only after all of its settings above have been preserved.
                  home.file.".codex/config.toml".force = true;

                  mcp-servers = {
                    programs = {
                      context7.enable = true;

                      nixos = {
                        enable = true;
                        env = {
                          MCP_NIXOS_TRANSPORT = "stdio";
                          FASTMCP_CHECK_FOR_UPDATES = "off";
                          FASTMCP_SHOW_SERVER_BANNER = "false";
                          FASTMCP_ENV_FILE = "/dev/null";
                        };
                      };

                      serena = {
                        enable = true;
                        context = "codex";
                        enableWebDashboard = false;
                        args = [ "--project-from-cwd" ];
                        extraPackages = [
                          pkgs.nixd
                          pkgs.nixfmt
                        ];
                        env = {
                          FASTMCP_ENV_FILE = "/dev/null";
                          SERENA_USAGE_REPORTING = "false";
                        };
                      };

                      textlint = {
                        enable = true;
                        settings.rules = { };
                      };
                    };

                    # Ponytail is not currently packaged by mcp-servers-nix;
                    # register its pinned local package through the module's
                    # freeform server settings.
                    settings.servers.ponytail = {
                      command = "${ponytailMcp}/bin/ponytail-mcp";
                      env.PONYTAIL_DEFAULT_MODE = "full";
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
