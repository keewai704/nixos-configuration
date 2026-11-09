{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  wallpaper = ./wallpaper.png;
  helium = inputs.helium.packages.x86_64-linux.helium-widevine;
in
{
  nixpkgs.overlays = [
    inputs.millennium.overlays.default
    inputs.nix-meltype.overlays.default
  ];

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

  hardware.i2c.enable = true;
  users.users.keewai.extraGroups = [ "i2c" ];

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
    fcitx5.addons = [ (pkgs.fcitx5-meltype.override { meltype = pkgs.meltype-bin; }) ];
    fcitx5.waylandFrontend = true;
    fcitx5.settings = {
      globalOptions."Hotkey/TriggerKeys"."0" = "Alt+grave";
      inputMethod = {
        "Groups/0".Name = "Default";
        "Groups/0"."Default Layout" = "us";
        "Groups/0".DefaultIM = "keyboard-us";
        "Groups/0/Items/0".Name = "keyboard-us";
        "Groups/0/Items/1".Name = "meltype";
      };
    };
  };

  environment.variables.QT_IM_MODULES = "wayland;fcitx";
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  environment.etc = lib.genAttrs [ "xdg/gtk-3.0/settings.ini" "xdg/gtk-4.0/settings.ini" ] (_: {
    text = lib.generators.toINI { } { Settings.gtk-im-module = "fcitx"; };
  });

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
    package = pkgs.millennium-steam;
    extraCompatPackages = [ inputs.chaotic.unrestrictedPackages.x86_64-linux.proton-cachyos ];
  };

  programs.dconf.enable = true;

  home-manager.users.keewai = {
    imports = [ inputs.nixcord.homeModules.nixcord ];

    services.searxng.enable = true;

    xdg.configFile."umbriel/config.toml".source =
      (pkgs.formats.toml { }).generate "umbriel-config.toml"
        {
          include = {
            files = [ "${config.programs.umbriel.package}/share/umbriel/config.toml" ];
            optional.files = [ "noctalia.toml" ];
          };
          output."Dell Inc. AW3926QW CMYQ7K4".mode = "5120x2160@165";
        };

    programs.gh.settings.browser = lib.mkForce "${lib.getExe' pkgs.systemd "systemd-run"} --user --collect --quiet ${lib.getExe helium}";

    programs.nixcord = {
      enable = true;
      discord.equicord.enable = true;
    };

    home.packages = [
      pkgs.bitwarden-desktop
      pkgs.ddcutil
      pkgs.kitty
      pkgs.spotify
      pkgs.wl-clipboard
      helium
    ];

    programs.noctalia = {
      enable = true;
      systemd.enable = true;
      settings = {
        brightness.enable_ddcutil = true;
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
