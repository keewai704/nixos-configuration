{
  config,
  inputs,
  lib,
  ...
}:
{
  imports = [ inputs.nixcord.homeModules.nixcord ];

  programs.nixcord = {
    enable = true;
    discord.enable = false;
    legcord = {
      enable = true;
      settings = {
        mods = [ "equicord" ];
        quickCss = true;
        windowStyle = "default";
      };
    };
  };

  stylix.targets.nixcord.enable = false;

  xdg.configFile = {
    "legcord/quickCss.css".text = lib.mkIf (!config.programs.island.enable) (
      import ./legcord-system24.nix {
        colors = config.lib.stylix.colors;
        fonts = config.stylix.fonts;
      }
    );
  };
}
