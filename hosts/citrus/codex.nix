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

        # Keep upstream hook mechanics, but inject the locally maintained skill.
        install -Dm644 \
          "${skillRoot}/ponytail/SKILL.md" \
          "$out/skills/ponytail/SKILL.md"
        install -Dm644 "${ponytailSource}/LICENSE" "$out/LICENSE"

        node --test "${ponytailSource}/tests/hooks.test.js"
        node - "$out" <<'NODE'
        const assert = require('node:assert/strict');
        const fs = require('node:fs');
        const root = process.argv[2];
        const { getPonytailInstructions } = require(root + '/hooks/ponytail-instructions.js');
        const body = fs.readFileSync(root + '/skills/ponytail/SKILL.md', 'utf8')
          .replace(/^---[\s\S]*?---\s*/, "");
        for (const mode of ['lite', 'full', 'ultra']) {
          assert.equal(getPonytailInstructions(mode), 'PONYTAIL MODE ACTIVE — level: ' + mode + '\n\n' + body);
        }
        NODE
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
    model = "gpt-6-astra";
    model_reasoning_effort = "ultra";
    plan_mode_reasoning_effort = "max";
    agents = {
      default_subagent_model = "gpt-5.6-luna";
      default_subagent_reasoning_effort = "max";
    };

    # Reviewed against the official Astra prompting guide on 2026-09-05:
    # https://developers.openai.com/api/docs/guides/latest-model#prompting-best-practices
    developer_instructions = ''
      GPT-6 Astraの推論能力を活かし、主担当が問題の理解、難しい設計判断、結果の統合、最終レビューまで責任を持つこと。クレジット節約のために明示された要件、品質、安全性、必要な検証を省略しないこと。

      作業依頼は実行の指示として扱い、既に許可された範囲を検証まで完了すること。通常の実装判断は文脈と既存パターンから決め、同じ許可を取り直さないこと。結果・範囲・権限を左右する情報が不足するときだけ簡潔に質問し、その回答に依存しない作業を進めること。追加承認が本当に必要な操作は、許可済みの準備を終えて具体的な成果物を示してから確認すること。途中の質問や修正は進行中の依頼に取り込み、明確な中止・置換がなければ元の目的も完了すること。

      スキルの一般的な推奨よりユーザーの明示指示を優先し、タスクに合うスキルと必要な参照だけを読むこと。スキルを理由に停止・確認・範囲縮小する場合は、該当するSKILL.mdのリンクと指示を示し、必須条件と自分の解釈を区別すること。ホスト境界、安全要件、実行権限を越えて進めないこと。

      並列化が時間短縮や品質向上に役立つ場合は、独立した具体的な作業をサブエージェントへ委任すること。単純・定型的な作業にはGPT-5.6 Lunaをreasoning effort=maxで優先し、高度な推論が必要な委任にはGPT-6 Astraをreasoning effort=maxで明示指定すること。委任先には目的、必要な背景、担当ファイル、許可範囲、完了条件を渡し、同じファイルの同時編集を避けること。主担当は独立した作業を続け、返された根拠と差分を確認して統合すること。use-chatgpt-5-6-proは明示指定、または行き詰まりに独立した見解が必要な場合に使い、通常のレビューはサブエージェントで行うこと。

      変更の振る舞いとリスクに合う検証を行い、リポジトリで必須のチェックは完了すること。既存テストを再利用し、実装の言い換えや軽微な文言変更だけのためにテストを増やさないこと。検証が通ったら、変更・失敗・未解決の懸念がない限り検証を繰り返したり広げたりしないこと。

      回答はユーザーの言語で、結果を先に、簡潔で具体的に書くこと。説明量は依頼に合わせ、必要な根拠、検証結果、未解決事項を残すこと。定型句や不要な見出しを避け、箇条書きや表は比較・手順が読みやすくなる場合に使うこと。

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
