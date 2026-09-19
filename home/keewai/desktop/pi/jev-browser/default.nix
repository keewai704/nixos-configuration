{ lib, pkgs, ... }:
let
  browser-harness = pkgs.callPackage ../../../../../pkgs/browser-harness { };
  jev-ultrafast = pkgs.callPackage ../../../../../pkgs/jev-ultrafast { inherit browser-harness; };
  brave = pkgs.callPackage ../../../../../pkgs/brave-origin { };
  python = pkgs.python3.withPackages (ps: [ (ps.toPythonModule jev-ultrafast) ]);
  runner = pkgs.writeShellApplication {
    name = "pi-jev-runner";
    runtimeInputs = [
      pkgs.procps
      pkgs.systemd
    ];
    text = ''
      while IFS='=' read -r name value; do
        case "$name" in
          DBUS_SESSION_BUS_ADDRESS | DISPLAY | HYPRLAND_INSTANCE_SIGNATURE | WAYLAND_DISPLAY | XAUTHORITY | XDG_CURRENT_DESKTOP | XDG_RUNTIME_DIR | XDG_SESSION_TYPE)
            export "$name=$value"
            ;;
        esac
      done < <(systemctl --user show-environment)
      exec ${lib.getExe python} -B ${./launch.py} ${lib.getExe' pkgs.systemd "systemd-run"} ${lib.getExe brave} ${./runner.py} "$@"
    '';
  };
in
{
  home.packages = [
    browser-harness
    jev-ultrafast
  ];
  home.file.".pi/agent/extensions/jev-browser.ts".source = pkgs.replaceVars ./extension.ts {
    runner = lib.getExe runner;
    systemdRun = lib.getExe' pkgs.systemd "systemd-run";
    systemctl = lib.getExe' pkgs.systemd "systemctl";
  };
}
