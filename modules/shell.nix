{ pkgs, ... }:

{
  users.users.keewai.shell = pkgs.zsh;
  programs.zsh = {
    enable = true;
    enableGlobalCompInit = false;
    promptInit = "";
  };
}
