{ inputs, osConfig, ... }:
{
  imports = [ inputs.hypr-island.homeManagerModules.default ];
  programs.dynamic-island = {
    enable = true;
    stylix.enable = true;
    hyprland.enable = true;
    lock = {
      enable = true;
      onStartup = true;
      fingerprint = osConfig.services.fprintd.enable;
    };
    settings = {
      notch = true;
      hover = true;
      dnd = false;
      reducedMotion = false;
    };
  };
}
