{
  inputs,
  pkgs,
  ...
}:
let
  wallpaper = ./wallpaper.png;
in
{
  imports = [ inputs.nix-hazkey.nixosModules.hazkey ];

  programs = {
    noctalia = {
      enable = true;
      recommendedServices.enable = true;
    };
    umbriel.enable = true;
  };

  services.displayManager.noctalia-greeter.enable = true;

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.settings.inputMethod = {
      "Groups/0".Name = "Default";
      "Groups/0"."Default Layout" = "us";
      "Groups/0".DefaultIM = "keyboard-us";
      "Groups/0/Items/0".Name = "keyboard-us";
      "Groups/0/Items/1".Name = "hazkey";
    };
  };

  services.hazkey.enable = true;

  fonts.packages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-cjk-serif
  ];

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
  };

  programs.steam = {
    enable = true;
    extraCompatPackages = [ inputs.chaotic.unrestrictedPackages.x86_64-linux.proton-cachyos ];
  };

  programs.dconf.enable = true;

  home-manager.users.keewai = {
    home.packages = [
      pkgs.kitty
      pkgs.spotify
      inputs.helium.packages.x86_64-linux.helium-widevine
    ];

    programs.noctalia = {
      enable = true;
      systemd.enable = true;
      settings = {
        shell.font_family = "JetBrainsMono Nerd Font";
        theme = {
          mode = "dark";
          source = "builtin";
          builtin = "Noctalia";
          templates = {
            enable_builtin_templates = true;
            builtin_ids = [
              "gtk"
              "kitty"
              "qt"
              "umbriel"
            ];
            enable_community_templates = true;
            community_ids = [
              "chromium-based"
              "claude-code"
              "codex"
              "fcitx5"
              "pi-agent"
            ];
          };
        };
        wallpaper = {
          enabled = true;
          default.path = "${wallpaper}";
        };
      };
    };
  };
}
