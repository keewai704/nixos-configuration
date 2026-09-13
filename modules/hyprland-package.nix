{ inputs, pkgs, ... }:
{
  nixpkgs.overlays = [
    (_final: _previous: {
      hyprland =
        inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland.overrideAttrs
          (old: {
            src = inputs.hyprland;
            patches = (old.patches or [ ]) ++ [ ../pkgs/hyprland/hyprland-ime-modifiers.patch ];
          });
    })
  ];
}
