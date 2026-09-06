{ pkgs, ... }:

{
  users.users.keewai.shell = pkgs.zsh;
  programs.zsh = {
    enable = true;
    # Home Manager initializes completion after adding the user's packages.
    enableGlobalCompInit = false;
    promptInit = ""; # Starship owns the interactive prompt.
  };

}
