{
  lib,
  pkgs,
  ...
}:

let
  cuaDriver = pkgs.callPackage ../pkgs/cua-driver/package.nix { };
  cuaEnvironment = {
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
          DBUS_SESSION_BUS_ADDRESS | DISPLAY | HYPRLAND_INSTANCE_SIGNATURE | WAYLAND_DISPLAY | XDG_CURRENT_DESKTOP | XDG_RUNTIME_DIR | XDG_SESSION_DESKTOP | XDG_SESSION_TYPE)
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
in
{
  services.gnome.at-spi2-core.enable = true;

  home-manager.users.keewai = {
    home = {
      packages = [ cuaDriver ];
      sessionVariables = cuaEnvironment;
    };

    systemd.user.sessionVariables = cuaEnvironment;

    mcp-servers.settings.servers.cua-driver = {
      command = lib.getExe cuaMcp;
      args = [ "mcp" ];
      env = cuaEnvironment;
    };
  };
}
