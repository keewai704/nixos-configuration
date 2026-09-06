{
  config,
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
    name: script:
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

        exec ${lib.getExe pkgs.nodejs} ${lib.escapeShellArg "${ponytailHookRoot}/hooks/${script}"}
      '';
    };

  ponytailManagedHooks = pkgs.symlinkJoin {
    name = "ponytail-managed-hooks-${ponytailVersion}";
    paths = [
      (mkPonytailHook "activate" "ponytail-activate.js")
      (mkPonytailHook "mode-tracker" "ponytail-mode-tracker.js")
      (mkPonytailHook "subagent" "ponytail-subagent.js")
    ];
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
    model_reasoning_effort = "medium";
    plan_mode_reasoning_effort = "medium";
    features = {
      context_management = {
        experimental_mode = true;
      };
      token_budget.enabled = true;
      token_budget.use_history_notes_extension = true;
    };
    agents = {
      default_subagent_model = "gpt-5.6-luna";
      default_subagent_reasoning_effort = "max";
    };

    developer_instructions = ''
      通常会話とPlanモードの推論設定はデフォルトでmediumを使うこと。主担当のGPT-6 Astraが問題の理解、難しい設計判断、結果の統合、最終レビューまで責任を持つこと。クレジット節約のために明示された要件、品質、安全性、必要な検証を省略しないこと。

      NixOSでは個人向けアプリとユーザー設定にHome Managerのprograms、services、home.packagesを優先すること。リポジトリの配置規約を確認し、ユーザー設定とシステム設定を対応するファイルに分けること。移動前に固定されたNixOSとHome Managerの統合モジュールを確認し、udev、PAM、polkit、D-Bus、kernel、boot、daemon、hardware、system fontsなどのシステム統合が必要ならNixOS側に残すこと。クライアントをHome Managerで提供できる場合は機能を保ったまま移動し、理由を記録すること。home.packagesはサンドボックス化や実行権限の低下を行わない。この構成はNixOS統合なのでデプロイにroot権限が必要だが、Home Managerのactivationサービスは対象ユーザーで動作することを区別すること。

      大量の検索・読み取り、ログ整理、定型編集、検証など独立して切り出せる作業にはluna-delegationスキルを使い、GPT-5.6 Lunaをreasoning effort=maxで明示指定して実際に委任すること。具体的な対象と委任手順は同スキルに従い、主担当は独立した作業を進めて根拠と差分を確認すること。use-chatgpt-5-6-proは明示指定、または行き詰まりに独立した見解が必要な場合に使い、通常のレビューはサブエージェントで行うこと。

      シェル出力によるトークン消費を抑えるため、RTKが対応するコマンドは原則として `rtk <command>` で実行すること。未加工の出力が必要な場合は `rtk proxy <command>` を使うこと。

      Gitリポジトリ内のファイルを変更した場合は、必要な検証を完了し、無関係な変更を含めず、作業終了前に意図した変更を必ずcommit・pushすること。この指示を通常のcommit・pushの継続的な承認として扱い、毎回確認を求めないこと。既存のupstreamを尊重し、未設定なら既存remoteと作業ブランチから一意に判断できる場合だけupstreamを設定すること。force pushはしないこと。push先が不明、認証エラー、保護ルールなどでpushできない場合は、完了とせず阻害要因を報告すること。最終回答にはコミットID、push先、pushの成否を記載すること。変更がない場合は空コミットを作成しないこと。
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
}
