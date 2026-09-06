{ pkgs, ... }:

{
  users.users.keewai.shell = pkgs.zsh;
  programs.zsh = {
    enable = true;
    # Home Manager initializes completion after adding the user's packages.
    enableGlobalCompInit = false;
  };

  home-manager.users.keewai = {
    home.packages = [
      pkgs.yt-dlp
      pkgs.zsh-completions
    ];

    programs = {
      zsh = {
        enable = true;
        enableCompletion = true;
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;
        defaultKeymap = "emacs";
        history = {
          size = 50000;
          ignoreAllDups = true;
        };
        initContent = ''
          zstyle ':completion:*' menu select
          zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
        '';
      };

      fzf = {
        enable = true;
        enableZshIntegration = true;
      };
      zoxide = {
        enable = true;
        enableZshIntegration = true;
      };
    };
  };
}
