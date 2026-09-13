{
  inputs,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  wallpaper = pkgs.callPackage ../../../pkgs/hyprpaper-shm { };
in
{
  # The SHM renderer works without a GPU render node or DMA-BUF protocol.
  services.hyprpaper = {
    package = wallpaper;
    settings = {
      preload = [ osConfig.stylix.image ];
      wallpaper = lib.mkForce [ ",${osConfig.stylix.image}" ];
    };
  };
  programs.dynamic-island.package = pkgs.callPackage "${inputs.dynamic-island}/package.nix" {
    hyprland = wallpaper.hyprctl;
  };
}
