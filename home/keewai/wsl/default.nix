{ lib, pkgs, ... }:
{
  home.packages = with pkgs; [
    wget
    which
    wsl-open
  ];

  home.sessionVariables.BROWSER = lib.getExe pkgs.wsl-open;
  programs.zsh.shellAliases.open = "wsl-open";
}
