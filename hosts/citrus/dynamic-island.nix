{ inputs, lib, ... }:
{
  imports = [ inputs.dynamic-island.nixosModules.default ];
  programs.dynamic-island.enable = true;
  # The upstream module already declares hyprlock's PAM service separately.
  # Home Manager owns hyprlock and hypridle; avoid a second global user service.
  programs.hyprlock.enable = lib.mkForce false;
}
