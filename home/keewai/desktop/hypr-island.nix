{ inputs, pkgs, ... }:
{
  imports = [ inputs.hypr-island.homeManagerModules.default ];
  programs.dynamic-island = {
    enable = true;
    package = (pkgs.callPackage "${inputs.hypr-island}/package.nix" { }).overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ../../../pkgs/hypr-island/disable-lock.patch ];
    });
    stylix.enable = true;
    hyprland.enable = true;
    lock.enable = false;
    settings = {
      notch = true;
      hover = true;
      dnd = false;
      reducedMotion = false;
    };
  };
}
