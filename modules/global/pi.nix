{
  inputs,
  pkgs,
  ...
}:

let
  piExtensions = pkgs.callPackage ../../pkgs/pi-extensions/package.nix { };
  piWeb = pkgs.callPackage ../../pkgs/pi-web/package.nix { };
  extensionRoot = "${piExtensions}/lib/node_modules";

  piLensSettings = {
    lsp.enabled = true;
    tools.lazy = false;
  };

  # Keep the baseline servers and helper commands on Pi's PATH. Pi-lens can
  # still install additional language servers on demand for other ecosystems.
  piLspPackages = with pkgs; [
    bash-language-server
    getconf
    marksman
    nixd
    nixfmt
    typescript-language-server
    vscode-langservers-extracted
    which
    yaml-language-server
  ];
  piSettings = {
    # This is Pi's provider ID for ChatGPT subscription authentication. It does
    # not install or invoke the Codex CLI.
    defaultProvider = "openai-codex";
    defaultModel = "gpt-5.6-sol";
    defaultThinkingLevel = "max";
    defaultProjectTrust = "always";
    defaultTools = [
      "read"
      "bash"
      "write"
    ];
    enabledModels = [ "openai-codex/gpt-5.6-sol" ];

    collapseChangelog = true;
    enableAnalytics = false;
    enableInstallTelemetry = false;
    quietStartup = true;
    npmCommand = [ "${pkgs.nodejs_24}/bin/npm" ];

    # Hashline installs the anchor-aware read/edit tools first. FFF loads after
    # it so override mode owns the final grep/find names and adds multi_grep.
    packages = [
      "${extensionRoot}/pi-hashline-edit-pro"
      "${extensionRoot}/@ff-labs/pi-fff"
      "${extensionRoot}/pi-mcp-adapter"
      "${extensionRoot}/pi-web-access"
      "${extensionRoot}/pi-background-tasks"
      "${extensionRoot}/pi-lens"
      "${extensionRoot}/pi-subagents"
      "${extensionRoot}/@juicesharp/rpiv-todo"
    ];

    skills = [ ../../skills ];
  };

  piGlobalInstructions = ''
    # Global tool-use policy

    - Use the dedicated `grep` and `find` tools for content and file-name searches instead of `bash`.
    - When matching multiple alternative words or patterns (logical OR), use `multi_grep` instead of issuing repeated searches.
    - If a search genuinely must run through `bash`, use `rg`; do not invoke `grep` or `find` from the shell.
    - After locating a relevant file or line, use `read` with `offset` and `limit` to inspect only the surrounding range. Read an entire file only when the task requires it.
    - When the exact path of a known file is outside the workspace, call `read` on that path directly instead of searching for it.
    - Do not use Pi's built-in whole-file `edit` tool. Use Hashline's anchored `replace` or `insert` tools for targeted edits.
  '';
in
{
  # Pi-lens downloads some upstream native language servers at runtime. nix-ld
  # and ICU let those managed ELF/.NET binaries run instead of hitting stub-ld.
  programs.nix-ld = {
    enable = true;
    libraries = [ pkgs.icu ];
  };

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
        ponytailMcp = pkgs.callPackage ../../pkgs/ponytail-mcp/package.nix { };
      in
      {
        imports = [
          inputs.mcp-servers-nix.homeManagerModules.default
        ];

        home = {
          packages = [
            pkgs.ffmpeg
            pkgs.pi-coding-agent
            piWeb
            pkgs.yt-dlp
          ]
          ++ piLspPackages;

          sessionVariables = {
            PI_FFF_MODE = "override";
            PI_FFF_MULTIGREP = "1";
            PI_TELEMETRY = "0";
            PI_WEB_HOSTNAME = "127.0.0.1";
            PI_WEB_NO_OPEN = "1";
            PI_WEB_SKIP_VERSION_CHECK = "1";
          };

          file = {
            ".pi/agent/AGENTS.md" = {
              text = piGlobalInstructions;
              force = true;
            };
            ".pi/agent/settings.json" = {
              source = (pkgs.formats.json { }).generate "pi-settings.json" piSettings;
              force = true;
            };
            ".pi-lens/config.json" = {
              source = (pkgs.formats.json { }).generate "pi-lens-settings.json" piLensSettings;
              force = true;
            };
          };

          activation.trustAllSerenaProjects = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
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

        systemd.user.sessionVariables = {
          PI_FFF_MODE = "override";
          PI_FFF_MULTIGREP = "1";
          PI_TELEMETRY = "0";
          PI_WEB_HOSTNAME = "127.0.0.1";
          PI_WEB_NO_OPEN = "1";
          PI_WEB_SKIP_VERSION_CHECK = "1";
        };

        programs.mcp.enable = true;

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
              context = "agent";
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

          # Ponytail is not provided by mcp-servers-nix, so register the local
          # package through its freeform server settings.
          settings.servers.ponytail = {
            command = "${ponytailMcp}/bin/ponytail-mcp";
            env.PONYTAIL_DEFAULT_MODE = "full";
          };
        };
      };
  };
}
