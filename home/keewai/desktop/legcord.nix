{ config, inputs, ... }:
{
  imports = [ inputs.nixcord.homeModules.nixcord ];

  programs.nixcord = {
    enable = true;
    discord.enable = false;
    legcord = {
      enable = true;
      equicord.enable = true;
      settings = {
        quickCss = true;
        windowStyle = "default";
      };
    };
  };

  stylix.targets.nixcord.enable = false;

  xdg.configFile = {
    "legcord/quickCss.css".text = import ./legcord-system24.nix {
      colors = config.lib.stylix.colors;
      fonts = config.stylix.fonts;
    };
  };
}
