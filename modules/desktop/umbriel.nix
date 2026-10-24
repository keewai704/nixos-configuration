{
  config,
  inputs,
  lib,
  pkgs,
  theme,
  ...
}:
let
  session = "${config.programs.umbriel.package}/bin/start-umbriel";
in
{
  imports = [ inputs.umbriel.nixosModules.default ];

  programs.umbriel.enable = true;

  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = session;
        user = "keewai";
      };
      default_session.command =
        "${lib.getExe pkgs.tuigreet} --time --remember"
        + " --theme ${lib.escapeShellArg theme.tuigreetTheme}"
        + " --cmd ${lib.escapeShellArg session}";
    };
  };

  system.preSwitchChecks.umbrielSessionMigration = ''
    case "$2" in
      test|switch|check)
        if [ -e /run/current-system/etc/systemd/user/wayland-wm@.service ] &&
           [ ! -e "$1/etc/systemd/user/wayland-wm@.service" ]; then
          echo "Refusing a live UWSM removal: it would terminate the desktop without re-arming greetd boot autologin."
          echo "Keep the current session and known-good boot entry. A controlled boot migration requires explicit authorization."
          exit 1
        fi
        ;;
    esac
  '';

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
