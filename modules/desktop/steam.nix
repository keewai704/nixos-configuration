{
  config,
  inputs,
  pkgs,
  ...
}:
{
  nixpkgs.overlays = [
    inputs.millennium.overlays.default
    (final: _previous: { millennium = final.local.millennium; })
  ];

  boot.kernelModules = [ "ntsync" ];

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
      extraCompatPackages = [
        pkgs.local.proton-wineland
      ];
    };
  };
}
