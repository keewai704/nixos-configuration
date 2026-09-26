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
}
