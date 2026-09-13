{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  skillRoot = ../../../skills;

  skillEntries =
    lib.mapAttrs'
      (
        name: _type:
        lib.nameValuePair ".agents/skills/${name}" {
          source = skillRoot + "/${name}";
          force = true;
        }
      )
      (
        lib.removeAttrs (builtins.readDir skillRoot) [
          "ponytail"
          "luna-delegation"
        ]
      );

  managedMcpNames = lib.attrNames config.programs.mcp.servers;
  managedMcpNameArgs = lib.escapeShellArgs managedMcpNames;
  userCodexConfig = "${config.home.homeDirectory}/.codex/config.toml";
in
{
  imports = [ inputs.mcp-servers-nix.homeManagerModules.default ];

  home = {
    file = skillEntries // {
      # sadjow's wrapper advertises this stable executable path to Codex.
      ".local/bin/codex".source = "${config.programs.codex.package}/bin/codex";
    };
    packages = [ pkgs.rtk ];

    # A user-level entry wins over /etc/codex/config.toml. Remove only
    # model, reasoning, and subagent overrides and duplicate MCP names,
    # while preserving bundled helpers and unrelated preferences.
    activation.removeUserCodexOverrides = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      user_config=${lib.escapeShellArg userCodexConfig}
      if [[ -f "$user_config" && -w "$user_config" ]]; then
        ${lib.getExe pkgs.yq-go} -i -p=toml -o=toml \
          'del(.model, .model_reasoning_effort, .plan_mode_reasoning_effort, .features.multi_agent)' \
          "$user_config"
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

  programs = {
    mcp.enable = true;

    # Install the CLI without generating a user config that shadows /etc/codex.
    codex = {
      enable = true;
      package = inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
      enableMcpIntegration = false;
    };
  };

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
      openaiDeveloperDocs.url = "https://developers.openai.com/mcp";
    };
  };
}
