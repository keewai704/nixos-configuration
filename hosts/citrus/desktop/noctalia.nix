{ inputs, pkgs, ... }:
let
  wallpaper = ./wallpaper.png;
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
            "bitwarden"
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
              "claude-code"
              "codex"
              "discord"
              "fastfetch"
              "fcitx5"
              "heroiclauncher"
              "papirus-icons"
              "pi-agent"
              "starship"
              "thunar"
              "zen-browser"
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
