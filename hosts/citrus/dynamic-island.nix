{ inputs, lib, ... }:
{
  imports = [ inputs.dynamic-island.nixosModules.default ];
  programs.dynamic-island.enable = true;
  programs.hyprlock.enable = lib.mkForce false;
}
