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

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
