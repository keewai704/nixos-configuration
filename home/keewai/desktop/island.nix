{ config, inputs, ... }:
{
  imports = [ inputs.island.homeManagerModules.default ];

  programs.island = {
    enable = true;
    wallpaper = config.stylix.image;
    bar.chips = {
      shape = "ring";
      figure = "hover";
    };
  };
}
