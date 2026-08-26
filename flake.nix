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
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      mcp-servers-nix,
      ...
    }:
    let
      system = "x86_64-linux";
      camofoxSharedUserId = "codex";
    in
    {
      nixosConfigurations.orange = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit camofoxSharedUserId; };
        modules = [
          ./hosts/orange/configuration.nix
          home-manager.nixosModules.home-manager
          (
            {
              config,
              lib,
              pkgs,
              ...
            }:
            let
              # Keep Codex's defaults in the system layer so its user config
              # remains writable for automatically persisted project trust.
              codexMcpServers = lib.mapAttrs (
                _name: server:
                lib.optionalAttrs (server.command != null) {
                  inherit (server) command args;
                }
                // lib.optionalAttrs (server.env != { }) { inherit (server) env; }
                // lib.optionalAttrs (server.url != null) { inherit (server) url; }
                // lib.optionalAttrs (server.headers != { }) { http_headers = server.headers; }
              ) config.home-manager.users.keewai.programs.mcp.servers;
              codexSystemSettings = {
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

                mcp_servers = codexMcpServers;
                projects."/home/keewai/nixos-configuration".trust_level = "trusted";
              };
            in
            {
              environment.etc."codex/config.toml".source =
                (pkgs.formats.toml { }).generate "codex-system-config"
                  codexSystemSettings;

              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;

                users.keewai =
                  {
                    config,
                    lib,
                    pkgs,
                    ...
                  }:
                  let
                    camofoxPackage = pkgs.callPackage ./hosts/orange/camofox-package.nix {
                      websockify = pkgs.python3Packages.websockify;
                    };
                    ponytailMcp = pkgs.callPackage ./pkgs/ponytail-mcp/package.nix { };
                    codexMutableConfig = "${config.xdg.stateHome}/codex/config.toml";
                    codexWrapper = pkgs.writeShellApplication {
                      name = "codex";
                      runtimeInputs = [
                        pkgs.coreutils
                        pkgs.gitMinimal
                        pkgs.util-linux
                        pkgs.yq-go
                      ];
                      text = ''
                        real_codex=/home/keewai/.nix-profile/bin/codex
                        mutable_config=${lib.escapeShellArg codexMutableConfig}
                        trust_dir=$PWD
                        read_cd_arg=false
                        umask 077

                        if [[ ! -x "$real_codex" ]]; then
                          printf 'Codex executable not found at %s\n' "$real_codex" >&2
                          exit 127
                        fi

                        for arg in "$@"; do
                          if [[ "$read_cd_arg" == true ]]; then
                            trust_dir=$arg
                            read_cd_arg=false
                            continue
                          fi

                          case "$arg" in
                            -C|--cd)
                              read_cd_arg=true
                              ;;
                            --cd=*)
                              trust_dir=''${arg#--cd=}
                              ;;
                            -C?*)
                              trust_dir=''${arg#-C}
                              ;;
                          esac
                        done

                        trust_dir=$(realpath -m -- "$trust_dir")
                        trust_root=$(git -C "$trust_dir" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$trust_dir")
                        trust_root=$(realpath -m -- "$trust_root")

                        if [[ ! -e "$mutable_config" ]]; then
                          install -Dm600 /dev/null "$mutable_config"
                        fi
                        chmod 600 "$mutable_config"

                        exec 9>"$mutable_config.lock"
                        flock 9
                        export CODEX_TRUST_DIR="$trust_dir"
                        export CODEX_TRUST_ROOT="$trust_root"
                        trust_filter='(.projects[strenv(CODEX_TRUST_DIR)].trust_level == "trusted") and (.projects[strenv(CODEX_TRUST_ROOT)].trust_level == "trusted")'

                        if ! yq -e -p=toml "$trust_filter" "$mutable_config" >/dev/null 2>&1; then
                          yq -i -p=toml -o=toml \
                            '.projects[strenv(CODEX_TRUST_DIR)].trust_level = "trusted" | .projects[strenv(CODEX_TRUST_ROOT)].trust_level = "trusted"' \
                            "$mutable_config"
                        fi

                        exec "$real_codex" "$@"
                      '';
                    };
                  in
                  {
                    imports = [
                      mcp-servers-nix.homeManagerModules.default
                    ];

                    home = {
                      stateVersion = "26.05";
                      sessionPath = [ "$HOME/.local/bin" ];
                      sessionVariables.CAMOFOX_URL = "http://127.0.0.1:9377";

                      file = {
                        ".codex/config.toml".source = config.lib.file.mkOutOfStoreSymlink codexMutableConfig;
                        ".local/bin/codex" = {
                          source = codexWrapper + "/bin/codex";
                          executable = true;
                        };
                      };

                      activation = {
                        initializeMutableCodexConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
                          if [[ ! -e ${lib.escapeShellArg codexMutableConfig} ]]; then
                            run ${pkgs.coreutils}/bin/install -Dm600 /dev/null \
                              ${lib.escapeShellArg codexMutableConfig}
                          fi
                        '';

                        trustAllSerenaProjects = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
                          serenaConfig="$HOME/.serena/serena_config.yml"
                          if [[ ! -e "$serenaConfig" ]]; then
                            run ${pkgs.coreutils}/bin/mkdir -p "$HOME/.serena"
                            run ${config.programs.mcp.servers.serena.command} init \
                              --language-backend LSP
                          fi
                          run ${pkgs.yq-go}/bin/yq --inplace \
                            '.trusted_project_path_patterns = ["**"]' \
                            "$serenaConfig"
                        '';
                      };
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
                    };

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
                      };

                      # These local packages are not currently provided by
                      # mcp-servers-nix, so register them through its freeform
                      # server settings.
                      settings.servers = {
                        camofox-browser = {
                          command = "${camofoxPackage}/bin/camofox-browser-mcp";
                          env = {
                            CAMOFOX_BASE_URL = "http://127.0.0.1:9377";
                            CAMOFOX_USER_ID = camofoxSharedUserId;
                            CAMOFOX_SESSION_KEY = "default";
                          };
                        };

                        ponytail = {
                          command = "${ponytailMcp}/bin/ponytail-mcp";
                          env.PONYTAIL_DEFAULT_MODE = "full";
                        };
                      };
                    };
                  };
              };
            }
          )
        ];
      };

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;
    };
}
