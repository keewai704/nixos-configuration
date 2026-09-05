{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  userName = "keewai";
  skillRoot = ../../skills;
  ponytailVersion = "4.9.0";
  ponytailSource = pkgs.fetchFromGitHub {
    owner = "DietrichGebert";
    repo = "ponytail";
    rev = "2ed6c52c9d7e5e56942508591085fd45dea277d3";
    hash = "sha256-bGdXvzhWPwGdz3T2Yh2h6lf+3PBRFAfdBxP5pESmCHI=";
  };
  ponytailHookRoot =
    pkgs.runCommand "ponytail-hooks-${ponytailVersion}"
      {
        nativeBuildInputs = [ pkgs.nodejs ];
      }
      ''
        mkdir -p "$out/hooks" "$out/skills/ponytail"

        for script in \
          ponytail-activate.js \
          ponytail-config.js \
          ponytail-instructions.js \
          ponytail-mode-tracker.js \
          ponytail-runtime.js \
          ponytail-subagent.js; do
          install -Dm644 "${ponytailSource}/hooks/$script" "$out/hooks/$script"
          node --check "$out/hooks/$script"
        done

        sed '/^argument-hint:/d' \
          "${ponytailSource}/skills/ponytail/SKILL.md" \
          > "$TMPDIR/ponytail-SKILL.md"
        cmp \
          "$TMPDIR/ponytail-SKILL.md" \
          "${skillRoot}/ponytail/SKILL.md"
        install -Dm644 \
          "${skillRoot}/ponytail/SKILL.md" \
          "$out/skills/ponytail/SKILL.md"
        install -Dm644 "${ponytailSource}/LICENSE" "$out/LICENSE"

        node --test "${ponytailSource}/tests/hooks.test.js"
      '';

  mkPonytailHook =
    name:
    pkgs.writeShellApplication {
      name = "ponytail-${name}";
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        pluginData="''${XDG_STATE_HOME:-$HOME/.local/state}/codex/plugins/ponytail"
        mkdir -p "$pluginData"

        export PLUGIN_ROOT=${lib.escapeShellArg "${ponytailHookRoot}"}
        export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
        export PLUGIN_DATA="$pluginData"
        export CLAUDE_PLUGIN_DATA="$pluginData"

        exec ${lib.getExe pkgs.nodejs} ${lib.escapeShellArg "${ponytailHookRoot}/hooks/ponytail-${name}.js"}
      '';
    };

  ponytailManagedHooks = pkgs.symlinkJoin {
    name = "ponytail-managed-hooks-${ponytailVersion}";
    paths = map mkPonytailHook [
      "activate"
      "mode-tracker"
      "subagent"
    ];
  };

  cuaDriver = pkgs.callPackage ../../pkgs/cua-driver { };
  cuaEnvironment = {
    CUA_DRIVER_PERMISSION_MODE = "standard";
    CUA_DRIVER_RS_ENABLE_WAYLAND = "1";
    CUA_DRIVER_RS_TELEMETRY_ENABLED = "false";
    CUA_DRIVER_RS_UPDATE_CHECK = "false";
  };

  cuaMcp = pkgs.writeShellApplication {
    name = "cua-driver-mcp";
    text = ''
      runtimeDir="/run/user/$(${pkgs.coreutils}/bin/id -u)"
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-$runtimeDir}"
      export DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

      while IFS='=' read -r name value; do
        case "$name" in
          DBUS_SESSION_BUS_ADDRESS | DISPLAY | HYPRLAND_INSTANCE_SIGNATURE | WAYLAND_DISPLAY | XAUTHORITY | XDG_CURRENT_DESKTOP | XDG_RUNTIME_DIR | XDG_SESSION_DESKTOP | XDG_SESSION_TYPE)
            export "$name=$value"
            ;;
        esac
      done < <(${pkgs.systemd}/bin/systemctl --user show-environment 2>/dev/null || true)

      if [[ -z "''${WAYLAND_DISPLAY:-}" ]]; then
        for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
          if [[ -S "$socket" ]]; then
            export WAYLAND_DISPLAY="''${socket##*/}"
            break
          fi
        done
      fi

      exec ${lib.getExe cuaDriver} "$@"
    '';
  };

  sharedMcpServers = config.home-manager.users.${userName}.programs.mcp.servers;

  toCodexMcpServer =
    name: server:
    let
      disabled = server.disabled or null;
      enabled = server.enabled or null;
    in
    lib.filterAttrs (_: value: value != null && value != [ ] && value != { }) (
      lib.removeAttrs server [
        "disabled"
        "headers"
        "serverUrl"
        "type"
      ]
      // lib.optionalAttrs ((server.headers or { }) != { }) {
        http_headers = server.headers;
      }
      // lib.optionalAttrs (enabled == null && disabled != null) {
        enabled = !disabled;
      }
      // lib.optionalAttrs (name == "cua-driver") {
        default_tools_approval_mode = "writes";
      }
    );

  codexSystemConfig = (pkgs.formats.toml { }).generate "chatgpt-desktop-mcp.toml" {
    developer_instructions = ''
      Codexクレジットの消費を抑えること。品質、安全性、検証の十分性を損なわない範囲で、単純・定型的な作業や、長時間でも独立して委任できる作業には、GPT-5.6 Lunaをreasoning effort=maxで優先的に活用すること。難しい設計判断、行き詰まりの解消、最終レビューなど、追加の高品質な推論が実質的に有益な場合に限り、use-chatgpt-5-6-proスキルでChatGPTのGPT-5.6 Sol Proを活用すること。

      シェル出力によるトークン消費を抑えるため、RTKが対応するコマンドは原則として `rtk <command>` で実行すること。未加工の出力が必要な場合は `rtk proxy <command>` を使うこと。

      Gitリポジトリ内のファイルを変更した場合は、無関係な変更を含めず、作業終了前に意図した変更を必ずコミットし、最終回答でコミットIDを報告すること。変更がない場合は空コミットを作成しないこと。
    '';
    mcp_servers = lib.mapAttrs toCodexMcpServer sharedMcpServers;
  };

  codexSystemRequirements = (pkgs.formats.toml { }).generate "codex-requirements.toml" {
    features.hooks = true;
    hooks = {
      managed_dir = "${ponytailManagedHooks}/bin";

      SessionStart = [
        {
          matcher = "startup|resume|clear|compact";
          hooks = [
            {
              type = "command";
              command = "${ponytailManagedHooks}/bin/ponytail-activate";
              timeout = 5;
              statusMessage = "Loading ponytail mode...";
            }
          ];
        }
      ];

      SubagentStart = [
        {
          hooks = [
            {
              type = "command";
              command = "${ponytailManagedHooks}/bin/ponytail-subagent";
              timeout = 5;
              statusMessage = "Loading ponytail mode...";
            }
          ];
        }
      ];

      UserPromptSubmit = [
        {
          hooks = [
            {
              type = "command";
              command = "${ponytailManagedHooks}/bin/ponytail-mode-tracker";
              timeout = 5;
              statusMessage = "Tracking ponytail mode...";
            }
          ];
        }
      ];
    };
  };
in
{
  # ChatGPT Desktop, Codex CLI, and the IDE extension all read this system
  # layer. Keep the user layer writable so the desktop app can persist its
  # own bundled MCP helpers, plugin state, project trust, and UI preferences.
  environment.etc = {
    "codex/config.toml".source = codexSystemConfig;
    "codex/requirements.toml".source = codexSystemRequirements;
    "codex/skills/ponytail".source = "${ponytailHookRoot}/skills/ponytail";
  };

  home-manager.users.${userName} =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      skillEntries = lib.mapAttrs' (
        name: _type:
        lib.nameValuePair ".agents/skills/${name}" {
          source = skillRoot + "/${name}";
          force = true;
        }
      ) (lib.removeAttrs (builtins.readDir skillRoot) [ "ponytail" ]);

      managedMcpNames = lib.attrNames config.programs.mcp.servers;
      managedMcpNameArgs = lib.escapeShellArgs managedMcpNames;
      userCodexConfig = "${config.home.homeDirectory}/.codex/config.toml";
    in
    {
      imports = [ inputs.mcp-servers-nix.homeManagerModules.default ];

      home = {
        file = skillEntries;
        packages = [
          cuaDriver
          pkgs.rtk
        ];
        sessionVariables = cuaEnvironment;

        # A user-level entry wins over /etc/codex/config.toml. Remove only
        # duplicate names owned by this module, while leaving ChatGPT's
        # bundled node_repl/cua_repl entries and every unrelated preference
        # untouched.
        activation.removeUserMcpOverrides = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          user_config=${lib.escapeShellArg userCodexConfig}
          if [[ -f "$user_config" && -w "$user_config" ]]; then
            for server_name in ${managedMcpNameArgs}; do
              export NIX_MANAGED_MCP_SERVER="$server_name"
              if ${lib.getExe pkgs.yq-go} -e -p=toml \
                '.mcp_servers[strenv(NIX_MANAGED_MCP_SERVER)] != null' \
                "$user_config" >/dev/null 2>&1; then
                ${lib.getExe pkgs.yq-go} -i -p=toml -o=toml \
                  'del(.mcp_servers[strenv(NIX_MANAGED_MCP_SERVER)])' \
                  "$user_config"
              fi
            done
            unset NIX_MANAGED_MCP_SERVER
            chmod 0600 "$user_config"
          fi
        '';
      };

      programs.mcp.enable = true;

      systemd.user.sessionVariables = cuaEnvironment;

      mcp-servers = {
        programs = {
          context7.enable = true;

          nixos = {
            enable = true;
            env = {
              FASTMCP_CHECK_FOR_UPDATES = "off";
              FASTMCP_SHOW_SERVER_BANNER = "false";
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

        settings.servers = {
          cua-driver = {
            command = lib.getExe cuaMcp;
            args = [ "mcp" ];
            env = cuaEnvironment;
          };

          openaiDeveloperDocs.url = "https://developers.openai.com/mcp";
        };
      };
    };
}
