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

      configFile = {
        "user-dirs.dirs".force = true;
        # Link only managed files so Fcitx5 can still save its other settings.
        fcitx5.recursive = true;

        "legcord/quickCss.css".text = import ./system24.nix {
          colors = config.lib.stylix.colors;
          fonts = config.stylix.fonts;
        };

        # SpaceTheme uses comma-separated RGB channels; keep its layout and plugins.
        "millennium/quick.css".source = config.lib.stylix.colors {
          template = pkgs.writeText "millennium.css.mustache" ''
            /* Managed by Stylix for SpaceTheme for Steam. */
            :root {
              --st-accent-1: {{base0D-rgb-r}}, {{base0D-rgb-g}}, {{base0D-rgb-b}} !important;
              --st-accent-2: {{base0E-rgb-r}}, {{base0E-rgb-g}}, {{base0E-rgb-b}} !important;
              --st-background: {{base00-rgb-r}}, {{base00-rgb-g}}, {{base00-rgb-b}} !important;
              --st-color-1: {{base00-rgb-r}}, {{base00-rgb-g}}, {{base00-rgb-b}} !important;
              --st-color-2: {{base01-rgb-r}}, {{base01-rgb-g}}, {{base01-rgb-b}} !important;
              --st-color-3: {{base00-rgb-r}}, {{base00-rgb-g}}, {{base00-rgb-b}} !important;
              --st-color-4: {{base01-rgb-r}}, {{base01-rgb-g}}, {{base01-rgb-b}} !important;
              --st-color-5: {{base02-rgb-r}}, {{base02-rgb-g}}, {{base02-rgb-b}} !important;
              --st-color-6: {{base03-rgb-r}}, {{base03-rgb-g}}, {{base03-rgb-b}} !important;
              --st-blue: {{base0D-rgb-r}}, {{base0D-rgb-g}}, {{base0D-rgb-b}} !important;
              --st-blue-hover: var(--st-blue) !important;
              --st-green: {{base0B-rgb-r}}, {{base0B-rgb-g}}, {{base0B-rgb-b}} !important;
              --st-green-hover: var(--st-green) !important;
              --st-red: {{base08-rgb-r}}, {{base08-rgb-g}}, {{base08-rgb-b}} !important;
              --st-red-hover: var(--st-red) !important;
              --st-yellow: {{base0A-rgb-r}}, {{base0A-rgb-g}}, {{base0A-rgb-b}} !important;
              --st-yellow-hover: var(--st-yellow) !important;
            }
            :root * {
              font-family: "${config.stylix.fonts.sansSerif.name}", sans-serif !important;
            }

            /* Steam now places controls beside FieldLeftColumn, outside FieldLabelRow. */
            :root body .DialogBody .eKmEXJCm_lgme24Fp_HWt {
              padding: 12px !important;
              margin-bottom: 12px !important;
              border-radius: var(--st-border-radius);
              background-color: rgb(var(--st-color-2));
            }
            body .DialogBody .eKmEXJCm_lgme24Fp_HWt ._2tALpM7z8naXJ35Pp5fNAG > :is(._2VcTlXFC64Jtg9gvtT6cmY, ._1W1to_azoBRG95oNAFpf9Q) {
              padding: 0 !important;
              background: none !important;
            }
            body .DialogBody .eKmEXJCm_lgme24Fp_HWt ._1W1to_azoBRG95oNAFpf9Q {
              margin-top: 6px;
            }
            /* Section headings also precede help text and inputs without a Panel wrapper. */
            body .DialogBody :is(.DialogSubHeader, .SettingsDialogSubHeader) {
              padding: 12px 0 6px;
              background: none;
            }
          '';
          extension = ".css";
        };
      };
    };

    programs.kitty.enable = true;

    programs.nixcord = {
      enable = true;
      discord.enable = false;
      legcord = {
        enable = true;
        equicord.enable = true;
        settings = {
          quickCss = true;
          windowStyle = "default";
        };
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
      # System24 maps its own palette to Discord's component colors.
      nixcord.enable = false;
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
