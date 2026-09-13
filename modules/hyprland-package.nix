{ inputs, pkgs, ... }:
{
  nixpkgs.overlays = [
    (_final: _previous: {
      hyprland = import ../pkgs/hyprland {
        hyprland = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
        src = inputs.hyprland;
      };
    })
  ];
}
