{ inputs, pkgs, ... }:
{
  nixpkgs.overlays = [
    (_final: _previous: {
      hyprland = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland.overrideAttrs {
        src = inputs.hyprland;
      };
    })
  ];
}
