{ inputs, ... }:
{
  imports = [ inputs.hypr-island.homeManagerModules.default ];

  programs.dynamic-island = {
    enable = true;
    stylix.enable = true;
    hyprland.enable = true;
    bitwarden.baseUrl = "https://orange.tail1e65cd.ts.net/vault";
    settings = {
      notch = true;
      hover = true;
      dnd = false;
      reducedMotion = false;
    };
  };

  services.hypridle = {
    enable = true;
    settings = {
      general.after_sleep_cmd = "hyprctl dispatch dpms on";
      listener = [
        {
          timeout = 660;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };
}
