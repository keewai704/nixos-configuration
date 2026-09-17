{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  theme = import ../../themes/tokyo-night-black {
    inherit pkgs;
    colors = config.lib.stylix.colors;
  };
  hyprlandSession = "${lib.getExe pkgs.uwsm} start -e -D Hyprland ${pkgs.hyprland}/bin/start-hyprland";
in
{
  nixpkgs.overlays = [
    (_final: _previous: {
      hyprland = import ../../pkgs/hyprland {
        hyprland = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
        src = inputs.hyprland;
      };
    })
  ];

  programs.hyprland = {
    enable = true;
    withUWSM = true;
    portalPackage =
      inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
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
