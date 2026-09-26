{ pkgs, ... }:
{
  users.users.keewai = {
    isNormalUser = true;
    description = "keewai";
    linger = true;
    shell = pkgs.zsh;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  programs.zsh = {
    enable = true;
    enableGlobalCompInit = false;
    promptInit = "";
  };
}
