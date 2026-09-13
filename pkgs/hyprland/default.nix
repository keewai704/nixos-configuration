{ hyprland, src }:
hyprland.overrideAttrs (old: {
  inherit src;
  patches = (old.patches or [ ]) ++ [ ./hyprland-ime-modifiers.patch ];
})
