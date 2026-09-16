{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  managedMcpNames = lib.attrNames config.programs.mcp.servers;
  managedMcpNameArgs = lib.escapeShellArgs managedMcpNames;
  userCodexConfig = "${config.home.homeDirectory}/.codex/config.toml";
in
{
  home = {
    file = {
      ".local/bin/codex".source = "${config.programs.codex.package}/bin/codex";
    };
    packages = [ pkgs.rtk ];

    activation.removeUserCodexOverrides = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      user_config=${lib.escapeShellArg userCodexConfig}
      if [[ -f "$user_config" && -w "$user_config" ]]; then
        ${lib.getExe pkgs.yq-go} -i -p=toml -o=toml \
          'del(.model, .model_reasoning_effort, .plan_mode_reasoning_effort)' \
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
    codex = {
      enable = true;
      package = inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
      enableMcpIntegration = false;
    };
  };
}
