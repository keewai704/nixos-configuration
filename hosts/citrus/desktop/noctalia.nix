{ inputs, pkgs, ... }:
let
  wallpaper = ./wallpaper.png;

  loginBox = output: cy: {
    inherit cy output;
    box_height = 196.0;
    box_width = 810.0;
    cx = 2560.0;
    placement_height = 2160.0;
    placement_width = 5120.0;
    rotation = 0.0;
    type = "login_box";
    settings = {
      background_color = "surface_container";
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
      show_password_reveal = true;
      show_session_buttons = true;
      show_unlock_hint = true;
      show_weather = true;
    };
  };
in
{
  programs.noctalia = {
    enable = true;
    recommendedServices.enable = true;
  };

  services.displayManager.noctalia-greeter.enable = true;

  home-manager.users.keewai = {
    home.packages = [
      pkgs.fastfetch
      pkgs.jq
    ];

    home.activation.fastfetchConfig = inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      fastfetch_conf="$HOME/.config/fastfetch/config.jsonc"
      if [ ! -e "$fastfetch_conf" ]; then
        run mkdir -p "$(dirname "$fastfetch_conf")"
        echo '{}' | run tee "$fastfetch_conf" > /dev/null
      fi
    '';

    programs.btop.settings.color_theme = "noctalia";

    programs.cava = {
      enable = true;
      settings.color.theme = "\"noctalia\"";
    };

    programs.noctalia = {
      enable = true;
      systemd.enable = true;
      settings = {
        bar.default = {
          start = [
            "wallpaper"
            "workspaces"
          ];
          end = [
            "media"
            "tray"
            "notifications"
            "network"
            "bluetooth"
            "volume"
            "brightness"
            "battery"
            "session"
          ];
          margin_ends = 800;
        };
        brightness.enable_ddcutil = true;
        calendar = {
          enabled = true;
          account.personal_google.type = "google";
        };
        control_center.hidden_tabs = [ "screen-time" ];
        desktop_widgets.enabled = false;
        location.auto_locate = true;
        lockscreen_widgets = {
          enabled = false;
          schema_version = 2;
          widget_order = [
            "lockscreen-login-box@DP-1"
            "lockscreen-login-box@DP-2"
          ];
          grid = {
            cell_size = 16;
            major_interval = 4;
            visible = true;
          };
          widget = {
            "lockscreen-login-box@DP-1" = loginBox "DP-1" 1887.0;
            "lockscreen-login-box@DP-2" = loginBox "DP-2" 1978.0;
          };
        };
        notification = {
          background_opacity = 0.8;
          keep_dismissed_in_history = false;
          position = "top_center";
        };
        osd = {
          background_opacity = 0.8;
          offset_y = 32;
          position = "bottom_center";
        };
        shell = {
          font_family = "Noto Sans CJK JP";
          polkit_agent = true;
          launcher = {
            search_position = "top";
            show_app_actions = true;
          };
          screenshot.save_to_file = false;
        };
        theme = {
          mode = "dark";
          shell_mode = "dark";
          source = "wallpaper";
          wallpaper_scheme = "soft";
          pure_black_dark = true;
          builtin = "Tokyo-Night";
          templates = {
            enable_builtin_templates = true;
            builtin_ids = [
              "btop"
              "cava"
              "gtk3"
              "gtk4"
              "kitty"
              "qt"
              "umbriel"
            ];
            enable_community_templates = true;
            community_ids = [
              "bat"
              "chromium-based"
              "claude-code"
              "codex"
              "discord"
              "fastfetch"
              "fcitx5"
              "papirus-icons"
              "pi-agent"
              "starship"
              "thunar"
            ];
          };
        };
        wallpaper = {
          enabled = true;
          default.path = "${wallpaper}";
        };
        widget.media.hide_when_no_media = true;
      };
    };
  };
}
