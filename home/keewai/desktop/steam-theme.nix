{ config, lib, ... }:
{
  xdg.configFile."millennium/quick.css".text = lib.mkIf (!config.programs.island.enable) (
    import ./steam-css.nix {
      colors = config.lib.stylix.colors;
      fonts = config.stylix.fonts;
    }
  );
}
