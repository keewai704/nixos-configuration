{ config, inputs, ... }:
{
  imports = [ inputs.island.homeManagerModules.default ];

  programs.island = {
    enable = true;
    wallpaper = config.stylix.image;
  };
}
