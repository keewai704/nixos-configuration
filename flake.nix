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
        specialArgs.hermesAgentSource = hermes-agent.outPath;
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
                  hermesSecretsFile = "${hermesHome}/secrets.env";
                  hermesBasePackage = hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
                  hindsightPostgres = pkgs.postgresql_18.withPackages (p: [ p.pgvector ]);

                  # Hermes rewrites URLs present in index.html for
                  # X-Forwarded-Prefix, but Vite's lazy-chunk preloader still
                  # defaults to root-relative /assets/* URLs. Build the web
                  # client with a relative base so every lazy route resolves
                  # beside the entry module under /hermes/assets/.
                  hermesPatchedWeb = hermesBasePackage.hermesWeb.overrideAttrs (old: {
                    postPatch = (old.postPatch or "") + ''
                      substituteInPlace web/vite.config.ts \
                        --replace-fail \
                          'export default defineConfig({' \
                          'export default defineConfig({ base: "./",'
                    '';
                  });

                  hermesPackage = hermesBasePackage.overrideAttrs (old: {
                    postInstall = (old.postInstall or "") + ''
                      rm "$out/share/hermes-agent/web_dist"
                      ln -s ${hermesPatchedWeb} "$out/share/hermes-agent/web_dist"
                    '';
                  });
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

                  # Read runtime secrets directly as process environment too.
                  # environmentFiles below also keeps the interactive Hermes
                  # CLI's .env in sync, while these unit directives ensure a
                  # secret rotation takes effect on the next service restart
                  # even when the Home Manager generation itself is unchanged.
                  systemd.user.services.hermes-agent.Service.EnvironmentFile = hermesSecretsFile;
                  systemd.user.services.hermes-backend.Service.EnvironmentFile = hermesSecretsFile;

                  systemd.user.services.hindsight-postgres = {
                    Unit.Description = "PostgreSQL for Hindsight memory";
                    Service = {
                      ExecStart = "${hindsightPostgres}/bin/postgres -D /home/keewai/.local/share/hindsight-postgres -h 127.0.0.1 -p 55432 -k /home/keewai/.local/share/hindsight-postgres";
                      Restart = "on-failure";
                      RestartSec = 5;
                    };
                    Install.WantedBy = [ "default.target" ];
                  };

                  systemd.user.services.hindsight-memory = {
                    Unit = {
                      Description = "Hindsight temporal knowledge-graph memory";
                      After = [ "hindsight-postgres.service" ];
                      Requires = [ "hindsight-postgres.service" ];
                    };
                    Service = {
                      Environment = [
                        "LD_LIBRARY_PATH=${
                          pkgs.lib.makeLibraryPath [
                            pkgs.stdenv.cc.cc.lib
                            pkgs.zlib
                          ]
                        }"
                        "HINDSIGHT_API_LLM_PROVIDER=openai-codex"
                        "HINDSIGHT_API_LLM_MODEL=gpt-5.6-sol"
                        "HINDSIGHT_API_EMBEDDINGS_PROVIDER=onnx"
                        "HINDSIGHT_API_EMBEDDINGS_ONNX_MODEL_ID=intfloat/multilingual-e5-small"
                        "HINDSIGHT_API_EMBEDDINGS_ONNX_DIMENSIONS=384"
                        "HINDSIGHT_API_RERANKER_PROVIDER=rrf"
                        "HINDSIGHT_API_DATABASE_URL=postgresql://keewai@127.0.0.1:55432/hindsight"
                      ];
                      ExecStart = "/home/keewai/.local/share/uv/tools/hindsight-embed/bin/hindsight-api --host 127.0.0.1 --port 8888";
                      Restart = "on-failure";
                      RestartSec = 5;
                    };
                    Install.WantedBy = [ "default.target" ];
                  };

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

                    # Secrets remain outside the Nix store. API_SERVER_KEY and
                    # HERMES_DASHBOARD_SESSION_TOKEN intentionally share one
                    # strong value because Hermes One uses it for the legacy
                    # API and dashboard transports, respectively.
                    environmentFiles = [ hermesSecretsFile ];
                    environment.CAMOFOX_URL = "http://127.0.0.1:9377";

                    settings = {
                      agent.max_turns = 150;
                      browser = {
                        cloud_provider = "camofox";
                        camofox.managed_persistence = false;
                      };
                      computer_use.backend = "cua";
                      compression.codex_responses_native = true;
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
                      memory.provider = "hindsight";
                      platforms.api_server = {
                        enabled = true;
                        extra = {
                          host = "127.0.0.1";
                          port = 8642;
                        };
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
