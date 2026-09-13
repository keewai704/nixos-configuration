{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  home.packages = [
    (pkgs.callPackage ../../../pkgs/apple-music-client {
      src = inputs.apple-music-client;
      authService = inputs.apple-music-client.packages.${pkgs.stdenv.hostPlatform.system}.auth-service;
    })
    inputs.apple-music-client.packages.${pkgs.stdenv.hostPlatform.system}.auth-service
  ];

  xdg.configFile = {
    "alac-room/theme.json".text = builtins.toJSON {
      colors = lib.getAttrs [
        "base00"
        "base01"
        "base02"
        "base03"
        "base04"
        "base05"
        "base06"
        "base07"
        "base08"
        "base09"
        "base0A"
        "base0B"
        "base0C"
        "base0D"
        "base0E"
        "base0F"
      ] config.lib.stylix.colors;
      fontFamily = config.stylix.fonts.sansSerif.name;
      fontSize = config.stylix.fonts.sizes.applications * 4.0 / 3.0;
      polarity = config.stylix.polarity;
    };
  };
}
