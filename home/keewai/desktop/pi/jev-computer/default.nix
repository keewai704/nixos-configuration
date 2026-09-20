{ lib, pkgs, ... }:
let
  python = pkgs.python3.withPackages (ps: [
    ps.pyatspi
    ps.pygobject3
  ]);
  driver = pkgs.writeShellApplication {
    name = "pi-jev-atspi";
    text = ''
      umask 077
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
      export DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
      export GI_TYPELIB_PATH=${
        lib.escapeShellArg (
          lib.makeSearchPath "lib/girepository-1.0" [
            pkgs.at-spi2-core
            pkgs.gobject-introspection
          ]
        )
      }
      exec ${lib.getExe' pkgs.util-linux "flock"} --nonblock --no-fork \
        "$XDG_RUNTIME_DIR/pi-jev.lock" ${lib.getExe python} -B ${./atspi.py}
    '';
  };
in
{
  home.file.".pi/agent/extensions/jev-computer.ts".source = pkgs.writeText "jev-computer.ts" (
    builtins.replaceStrings
      [
        "@driver@"
        "../../../shared/pi/extensions/jev-analysis.ts"
      ]
      [
        (lib.getExe driver)
        "${../../../shared/pi/extensions/jev-analysis.ts}"
      ]
      (builtins.readFile ./extension.ts)
  );
}
