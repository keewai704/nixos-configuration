{
  config,
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

  services.greetd.settings.initial_session = {
    command = "${config.programs.umbriel.package}/bin/start-umbriel";
    user = "keewai";
  };

  services.keyd = {
    enable = true;
    keyboards.su75-ultra = {
      ids = [ "k:1ca6:3007" ];
      settings.global.disable_modifier_guard = 1;
    };
  };

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.settings = {
      globalOptions."Hotkey/TriggerKeys"."0" = "Alt+grave";
      inputMethod = {
        "Groups/0".Name = "Default";
        "Groups/0"."Default Layout" = "us";
        "Groups/0".DefaultIM = "keyboard-us";
        "Groups/0/Items/0".Name = "keyboard-us";
        "Groups/0/Items/1".Name = "hazkey";
      };
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
    services.searxng.enable = true;

    xdg.configFile."umbriel/config.toml".source =
      (pkgs.formats.toml { }).generate "umbriel-config.toml"
        {
          include.files = [ "${config.programs.umbriel.package}/share/umbriel/config.toml" ];
          output."Dell Inc. AW3926QW CMYQ7K4".mode = "5120x2160@165";
        };

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
