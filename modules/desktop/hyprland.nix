{
  inputs,
  lib,
  pkgs,
  theme,
  ...
}:
let
  hyprlandSession = "${lib.getExe pkgs.uwsm} start -e -D Hyprland ${pkgs.hyprland}/bin/start-hyprland";
  hyprlandPackages = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  nixpkgs.overlays = [
    (_final: _previous: {
      inherit (hyprlandPackages) hyprland;
    })
  ];

  programs.hyprland = {
    enable = true;
    withUWSM = true;
    portalPackage = hyprlandPackages.xdg-desktop-portal-hyprland;
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
