{
  config,
  inputs,
  pkgs,
  ...
}:
let
  theme = import ./theme.nix {
    inherit pkgs;
    colors = config.lib.stylix.colors;
  };
in
{
  imports = [ inputs.stylix.homeModules.stylix ];

  # Personal themes also work on hosts without the NixOS Stylix module.
  stylix = theme.stylix // {
    overlays.enable = false; # NixOS owns pkgs with useGlobalPkgs = true.
  };
}
