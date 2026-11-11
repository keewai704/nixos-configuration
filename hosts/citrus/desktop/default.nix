{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  helium = inputs.helium.packages.x86_64-linux.helium-widevine;
in
{
  imports = [
    ./noctalia.nix
    ./steam.nix
    ./theme.nix
  ];

  nixpkgs.overlays = [ inputs.nix-meltype.overlays.default ];

  programs.umbriel.enable = true;

  services.greetd.settings.initial_session = {
    command = "${config.programs.umbriel.package}/bin/start-umbriel";
    user = "keewai";
  };

  hardware.i2c.enable = true;
  users.users.keewai.extraGroups = [
    "gamemode"
    "i2c"
  ];

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
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
  };

  fonts.packages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-cjk-serif
    pkgs.udev-gothic
  ];
  fonts.fontconfig.defaultFonts.sansSerif = [ "Noto Sans CJK JP" ];

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
  };

  boot.kernelModules = [ "ntsync" ];

  programs.gamemode = {
    enable = true;
    enableRenice = true;
    settings.general.renice = 10;
  };

  programs.dconf.enable = true;

  programs.thunar.enable = true;
  programs.xfconf.enable = true;
  services.gvfs.enable = true;
  services.tumbler.enable = true;
  xdg.mime.defaultApplications."inode/directory" = "thunar.desktop";

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
          output."Dell Inc. AW3926QW CMYQ7K4" = {
            mode = "5120x2160@165";
            vrr = "fullscreen";
            hdr = "auto";
          };
          layout.scrolling.default_extent_fraction = 0.333;
          input.cursor = {
            inherit (config.home-manager.users.keewai.home.pointerCursor) size;
            theme = config.home-manager.users.keewai.home.pointerCursor.name;
          };
          input.focus = {
            follows_mouse = true;
            hover_raises = false;
          };
          effects.preset.glass = {
            kind = "window";
            shader = "${./glass.glsl}";
          };
          window_rule = [
            {
              match.is_focused = false;
              opacity = 0.9;
              window_effect = "glass";
            }
          ];
          keybinds = {
            "Alt+bracketleft" = "spawn noctalia msg brightness-down";
            "Alt+bracketright" = "spawn noctalia msg brightness-up";
            "Mod+V" = {
              action = "spawn noctalia msg panel-toggle clipboard";
              repeat = false;
            };
            "Print" = {
              action = "spawn noctalia msg screenshot-fullscreen all";
              repeat = false;
            };
            "Alt+Print" = {
              action = "spawn noctalia msg screenshot-window";
              repeat = false;
            };
            "Alt+Sys_Req" = {
              action = "spawn noctalia msg screenshot-window";
              repeat = false;
            };
            "Mod+Shift+S" = {
              action = "spawn noctalia msg screenshot-region";
              repeat = false;
            };
          };
        };

    xdg.configFile."kitty/font.conf".text = ''
      font_family UDEV Gothic
    '';

    home.activation.kittyFontInclude = inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      kitty_conf="$HOME/.config/kitty/kitty.conf"
      grep -qxsF 'include font.conf' "$kitty_conf" \
        || echo 'include font.conf' | run tee -a "$kitty_conf" > /dev/null
    '';

    programs.gh.settings.browser = lib.mkForce "${lib.getExe' pkgs.systemd "systemd-run"} --user --collect --quiet ${lib.getExe helium}";

    programs.nixcord = {
      enable = true;
      discord.equicord.enable = true;
    };

    programs.mangohud = {
      enable = true;
      settings.toggle_hud = "Home";
    };

    home.packages = [
      pkgs.bitwarden-desktop
      pkgs.ddcutil
      pkgs.kitty
      pkgs.spotify
      pkgs.wl-clipboard
      helium
    ];
  };
}
