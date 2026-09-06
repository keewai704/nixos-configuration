{ pkgs, ... }:
{
  xdg.configFile."starship.toml".source = ./starship.toml;

  home.packages = [
    pkgs.btop
    pkgs.duf
    pkgs.dust
    pkgs.fd
    pkgs.zsh-completions
  ];

  programs = {
    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      historySubstringSearch.enable = true;
      plugins = [
        {
          name = "zsh-nix-shell";
          src = pkgs.zsh-nix-shell;
          file = "share/zsh-nix-shell/nix-shell.plugin.zsh";
        }
      ];
      defaultKeymap = "emacs";
      shellAliases = {
        cat = "bat --paging=never";
        tree = "eza --tree";
        du = "dust";
        df = "duf";
        top = "btop";
        ff = "fd";
      };
      history = {
        size = 50000;
        ignoreAllDups = true;
      };
      initContent = ''
        zstyle ':completion:*' menu select
        zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
      '';
    };

    bat.enable = true;
    starship = {
      enable = true;
      enableZshIntegration = true;
    };
    eza = {
      enable = true;
      enableZshIntegration = true; # ls, ll, la, lla, lt
      extraOptions = [ "--group-directories-first" ];
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
}
