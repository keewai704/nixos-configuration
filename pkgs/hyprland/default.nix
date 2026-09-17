{ hyprland, src }:
hyprland.overrideAttrs (previousAttrs: {
  inherit src;
  patches = (previousAttrs.patches or [ ]) ++ [ ./hyprland-ime-modifiers.patch ];
})
