{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  skillRoot = ../../../skills;

  cuaDriver = pkgs.callPackage ../../../pkgs/cua-driver { };
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
    # reasoning overrides and duplicate MCP names owned by this module,
    # while preserving bundled helpers and unrelated preferences.
    activation.removeUserCodexOverrides = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      user_config=${lib.escapeShellArg userCodexConfig}
      if [[ -f "$user_config" && -w "$user_config" ]]; then
        ${lib.getExe pkgs.yq-go} -i -p=toml -o=toml \
          'del(.model_reasoning_effort, .plan_mode_reasoning_effort)' \
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
}
