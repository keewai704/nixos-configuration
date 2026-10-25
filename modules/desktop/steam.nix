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
      package = pkgs.millennium-steam.override {
        extraArgs = "-language japanese";
        extraEnv = {
          DXVK_HDR = "1";
          LANG = "ja_JP.UTF-8";
          LANGUAGE = "ja_JP:ja";
          LC_ALL = "ja_JP.UTF-8";
          HOST_LC_ALL = "ja_JP.UTF-8";
        };
      };
      fontPackages = config.stylix.fonts.packages ++ [ pkgs.noto-fonts ] ++ config.fonts.packages;
      extraPackages = [ pkgs.gamescope ];
      extraCompatPackages = [
        pkgs.local.proton-wineland
      ];
    };
  };
}
