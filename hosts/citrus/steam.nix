{
  config,
  inputs,
  pkgs,
  ...
}:
{
  programs = {
    gamescope = {
      enable = true;
      enableWsi = true;
    };

    steam = {
      enable = true;
      package = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.millennium-steam;
      fontPackages = config.stylix.fonts.packages ++ [ pkgs.noto-fonts ] ++ config.fonts.packages;
      extraPackages = [ pkgs.gamescope ];
      extraCompatPackages = [ pkgs.proton-ge-bin ];
    };
  };
}
