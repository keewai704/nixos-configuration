{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  userName = "keewai";
  skillRoot = ../skills;
  cuaDriver = pkgs.callPackage ../pkgs/cua-driver { };
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
    mcp_servers = lib.mapAttrs toCodexMcpServer sharedMcpServers;
  };
in
{
  imports = [ inputs.home-manager.nixosModules.home-manager ];

  # ChatGPT Desktop, Codex CLI, and the IDE extension all read this system
  # layer. Keep the user layer writable so the desktop app can persist its
  # own bundled MCP helpers, plugin state, project trust, and UI preferences.
  environment.etc."codex/config.toml".source = codexSystemConfig;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.${userName} =
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
        ) (builtins.readDir skillRoot);

        managedMcpNames = lib.attrNames config.programs.mcp.servers;
        managedMcpNameArgs = lib.escapeShellArgs managedMcpNames;
        userCodexConfig = "${config.home.homeDirectory}/.codex/config.toml";
      in
      {
        imports = [ inputs.mcp-servers-nix.homeManagerModules.default ];

        home = {
          stateVersion = "26.05";
          file = skillEntries;
          packages = [ cuaDriver ];
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
  };
}
