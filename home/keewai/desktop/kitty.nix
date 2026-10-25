{ lib, pkgs, ... }:
{
  programs.kitty = {
    enable = true;
    settings = {
      remember_window_size = false;
      background_opacity = 0.9;
      dynamic_background_opacity = true;
    };
    extraConfig = ''
      include themes/noctalia.conf
    '';
    font = {
      package = lib.mkForce pkgs.hackgen-nf-font;
      name = lib.mkForce "HackGen Console NF";
      size = lib.mkForce 12;
    };
  };

  stylix.targets.kitty.enable = true;
}
