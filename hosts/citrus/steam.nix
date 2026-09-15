{
  config,
  inputs,
  pkgs,
  ...
}:
{
  nixpkgs.overlays = [ inputs.millennium.overlays.default ];

  programs = {
    gamescope = {
      enable = true;
      enableWsi = true;
    };

    steam = {
      enable = true;
      package = pkgs.millennium-steam;
      fontPackages = config.stylix.fonts.packages ++ [ pkgs.noto-fonts ] ++ config.fonts.packages;
      extraPackages = [ pkgs.gamescope ];
      extraCompatPackages = [ pkgs.proton-ge-bin ];
    };
  };
}
