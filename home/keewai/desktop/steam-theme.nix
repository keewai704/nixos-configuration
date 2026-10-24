{ config, ... }:
{
  xdg.configFile."millennium/quick.css".text = import ./steam-css.nix {
    colors = config.lib.stylix.colors;
    fonts = config.stylix.fonts;
  };
}
