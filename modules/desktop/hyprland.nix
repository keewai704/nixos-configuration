{
  lib,
  pkgs,
  ...
}:
let
  theme = import ../../themes/tokyo-night-black { inherit pkgs; };
  hyprlandSession = "${lib.getExe pkgs.uwsm} start -e -D Hyprland ${pkgs.hyprland}/bin/start-hyprland";
in
{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  services = {
    greetd = {
      enable = true;
      settings = {
        initial_session = {
          command = hyprlandSession;
          user = "keewai";
        };

        default_session = {
          command =
            "${lib.getExe pkgs.tuigreet} --time --remember --remember-user-session"
            + " --theme ${lib.escapeShellArg theme.tuigreetTheme}"
            + " --cmd ${lib.escapeShellArg hyprlandSession}";
        };
      };
    };
  };

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
