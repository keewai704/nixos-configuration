{
  config,
  osConfig,
  pkgs,
  ...
}:
{
  programs.noctalia = {
    enable = true;
    systemd.enable = true;
    settings = {
      shell = {
        font_family = config.stylix.fonts.sansSerif.name;
        launch_apps_as_systemd_services = true;
        setup_wizard_enabled = false;
        polkit_agent = true;
      };
      theme = {
        mode = "dark";
        source = "builtin";
        builtin = "Catppuccin";
        templates = {
          enable_builtin_templates = true;
          builtin_ids = [
            "gtk3"
            "gtk4"
            "qt"
            "hyprland"
          ];
          user.kitty = {
            input_path = "${config.programs.noctalia.package}/share/noctalia/assets/templates/kitty/kitty.conf";
            output_path = "$XDG_CONFIG_HOME/kitty/themes/noctalia.conf";
            post_hook = "${pkgs.procps}/bin/pkill -USR1 -x kitty || true";
          };
        };
      };
      wallpaper = {
        enabled = true;
        default.path = "${config.stylix.image}";
      };
      brightness.enable_ddcutil = osConfig.hardware.i2c.enable;
      lockscreen = {
        enabled = true;
        lock_before_suspend = true;
        fingerprint = osConfig.services.fprintd.enable;
      };
      idle.behavior = {
        lock = {
          enabled = true;
          timeout = 600;
          action = "lock";
        };
        screen-off = {
          enabled = true;
          timeout = 660;
          action = "screen_off";
        };
      };
      hooks = {
        started = "noctalia msg session lock";
        colors_changed = "${pkgs.hyprland}/bin/hyprctl reload";
      };
    };
  };

  gtk = {
    enable = true;
    theme = {
      package = pkgs.adw-gtk3;
      name = "adw-gtk3-dark";
    };
    gtk3.extraCss = ''@import url("noctalia.css");'';
    gtk4.extraCss = ''@import url("noctalia.css");'';
  };

  qt = {
    enable = true;
    platformTheme.name = "qtct";
    qt5ctSettings.Appearance = {
      color_scheme_path = "${config.xdg.configHome}/qt5ct/colors/noctalia.conf";
      custom_palette = true;
      standard_dialogs = "xdgdesktopportal";
    };
    qt6ctSettings.Appearance = {
      color_scheme_path = "${config.xdg.configHome}/qt6ct/colors/noctalia.conf";
      custom_palette = true;
      standard_dialogs = "xdgdesktopportal";
    };
  };
}
