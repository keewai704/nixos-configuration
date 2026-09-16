{ quickshell }:
quickshell.overrideAttrs (previousAttrs: {
  patches = (previousAttrs.patches or [ ]) ++ [ ./hyprland-workspace-address.patch ];
})
