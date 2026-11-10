{
  config,
  lib,
  pkgs,
  ...
}:
let
  iconTheme = "Papirus-Dark";

  terminalColor = name: "{{colors.terminal_${name}.default.hex}}";

  starshipConfig = pkgs.writeText "starship-noctalia.toml" ''
    palette = "noctalia"

    ${builtins.readFile ../../../home/keewai/common/shell/starship.toml}
    [palettes.noctalia]
    ${lib.concatStrings (
      lib.mapAttrsToList (name: value: "${name} = \"${value}\"\n") (
        lib.genAttrs [
          "black"
          "red"
          "green"
          "yellow"
          "blue"
          "magenta"
          "cyan"
          "white"
        ] (name: terminalColor "normal_${name}")
        // {
          bright-black = terminalColor "bright_black";
        }
      )
    )}
  '';

  qtctConfig =
    name:
    lib.generators.toINI { } {
      Appearance = {
        color_scheme_path = "${config.users.users.keewai.home}/.config/${name}/colors/noctalia.conf";
        custom_palette = true;
        icon_theme = iconTheme;
        style = "Fusion";
      };
    };
in
{
  qt = {
    enable = true;
    platformTheme = "qt5ct";
  };

  environment.etc = lib.genAttrs [ "xdg/gtk-3.0/settings.ini" "xdg/gtk-4.0/settings.ini" ] (_: {
    text = lib.generators.toINI { } {
      Settings = {
        gtk-icon-theme-name = iconTheme;
        gtk-im-module = "fcitx";
      };
    };
  });

  home-manager.users.keewai = {
    home.packages = [
      pkgs.adw-gtk3
      pkgs.papirus-icon-theme
    ];

    dconf.settings."org/gnome/desktop/interface".icon-theme = iconTheme;

    xdg.configFile = {
      "starship.toml".enable = false;
      "qt5ct/qt5ct.conf".text = qtctConfig "qt5ct";
      "qt6ct/qt6ct.conf".text = qtctConfig "qt6ct";
    };

    programs.nixcord.config.enabledThemes = [ "noctalia.theme.css" ];

    programs.noctalia.settings.theme = {
      mode = "dark";
      source = "builtin";
      builtin = "Noctalia";
      templates = {
        enable_builtin_templates = true;
        builtin_ids = [
          "gtk3"
          "gtk4"
          "kitty"
          "qt"
          "umbriel"
        ];
        enable_community_templates = true;
        community_ids = [
          "chromium-based"
          "claude-code"
          "codex"
          "discord"
          "fcitx5"
          "papirus-icons"
          "pi-agent"
          "thunar"
        ];
        user.starship = {
          input_path = "${starshipConfig}";
          output_path = "$XDG_CONFIG_HOME/starship.toml";
        };
      };
    };
  };
}
