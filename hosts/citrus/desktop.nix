{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  theme = import ./theme.nix {
    inherit pkgs;
    colors = config.lib.stylix.colors;
  };
  chatgptDesktop = pkgs.callPackage ../../pkgs/chatgpt-desktop { };
in
{
  nixpkgs.config.allowUnfreePredicate =
    package:
    builtins.elem (lib.getName package) [
      "chatgpt-desktop"
      "cuda_nvml_dev"
      "nvidia-x11"
      "nvidia-settings"
    ];

  environment.systemPackages = [
    chatgptDesktop
    pkgs.ddcutil
    pkgs.xarchiver
  ];

  home-manager.users.keewai = {
    imports = [ inputs.nixcord.homeModules.nixcord ];

    # Reuse the system's Hazkey package and UWSM autostart; Stylix owns the UI.
    i18n.inputMethod = {
      inherit (config.i18n.inputMethod) enable type;
      fcitx5 = {
        inherit (config.i18n.inputMethod.fcitx5) addons waylandFrontend;
        systemd.enable = false;
      };
    };

    # Steam reads user fontconfig; keep semibold Japanese text in the sans family.
    fonts.fontconfig = {
      enable = true;
      defaultFonts.sansSerif = config.fonts.fontconfig.defaultFonts.sansSerif ++ [ "Noto Sans CJK JP" ];
    };

    xdg = {
      userDirs = {
        enable = true;
        createDirectories = true;
      };

      configFile."user-dirs.dirs".force = true;
      # Link only managed files so Fcitx5 can still save its other settings.
      configFile.fcitx5.recursive = true;
    };

    programs.kitty.enable = true;

    programs.nixcord = {
      enable = true;
      discord.enable = false;
      legcord = {
        enable = true;
        equicord.enable = true;
      };
    };

    programs.noctalia = {
      enable = true;
      systemd.enable = true;
      settings = {
        bar.default.background_opacity = 0.68999998457729816;
        bar.default.margin_ends = 1200;
        calendar = {
          enabled = true;
          account.personal_google.type = "google";
        };
        control_center.calendar.event_date_format = "%m/%d (%a)";
        desktop_widgets.enabled = false;
        location.auto_locate = true;
        lockscreen.blurred_desktop = true;
        lockscreen_widgets = {
          enabled = false;
          schema_version = 2;
          widget_order = [ "lockscreen-login-box@DP-1" ];
          grid = {
            cell_size = 16;
            major_interval = 4;
            visible = true;
          };
          widget."lockscreen-login-box@DP-1" = {
            box_height = 196.0;
            box_width = 810.0;
            cx = 960.0;
            cy = 898.0;
            output = "DP-1";
            placement_height = 1080.0;
            placement_width = 1920.0;
            rotation = 0.0;
            type = "login_box";
            settings = {
              background_color = "surface_variant";
              background_opacity = 0.88;
              background_radius = 12.0;
              center_password_text = false;
              input_opacity = 1.0;
              input_radius = 6.0;
              layout = "regular";
              show_caps_lock = true;
              show_keyboard_layout = true;
              show_login_button = true;
              show_media = true;
              show_session_buttons = true;
              show_unlock_hint = true;
              show_weather = true;
            };
          };
        };
        notification.position = "top_center";
        shell = {
          font_family = config.stylix.fonts.sansSerif.name;
          launch_apps_as_systemd_services = true;
          panel_anchor_bar = "default";
          polkit_agent = true;
          launcher.compact = true;
          panel.polkit_placement = "attached";
        };
        theme = {
          mode = config.stylix.polarity;
          source = "custom";
          custom_palette = "Stylix";
          pure_black_dark = false;
          templates = {
            enable_builtin_templates = false;
            enable_community_templates = false;
          };
        };
        wallpaper = {
          enabled = true;
          default.path = toString config.stylix.image;
          last.path = toString config.stylix.image;
          monitors.DP-1.path = toString config.stylix.image;
        };
      };
      customPalettes.Stylix = theme.noctaliaPalette;
    };

    gtk = {
      colorScheme = "dark";
      gtk2.enable = false;
    };

    stylix.targets = {
      fcitx5.enable = true;
      firefox.enable = false;
      gtk = {
        enable = true;
        flatpakSupport.enable = false;
      };
      hyprland.enable = false;
      kitty.enable = true;
      qt = {
        enable = true;
        standardDialogs = "xdgdesktopportal";
      };
    };
  };

  programs = {
    dconf.enable = true;

    gamescope = {
      enable = true;
      enableWsi = true;
    };

    steam = {
      enable = true;
      package = inputs.millennium.packages.${pkgs.stdenv.hostPlatform.system}.millennium-steam;
      extraPackages = [ pkgs.gamescope ];
      extraCompatPackages = [ inputs.proton-cachyos.packages.${pkgs.stdenv.hostPlatform.system}.default ];
    };

    thunar = {
      enable = true;
      plugins = [
        pkgs.thunar-archive-plugin
        pkgs.thunar-volman
      ];
    };
  };

  services = {
    gnome.at-spi2-core.enable = true;
    gnome.gnome-keyring.enable = true;
    gvfs.enable = true;
    tumbler.enable = true;
  };

  xdg.mime.defaultApplications."inode/directory" = "thunar.desktop";
}
