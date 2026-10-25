{
  config,
  inputs,
  lib,
  theme,
  ...
}:
{
  imports = [
    inputs.noctalia.homeModules.default
    ./japanese.nix
    ./templates
  ];

  programs.noctalia = {
    enable = true;
    systemd.enable = true;
    settings = {
      shell = {
        font_family = config.stylix.fonts.sansSerif.name;
        time_format = "{:%H:%M}";
      };
      theme = {
        mode = "dark";
        source = "custom";
        custom_palette = "TokyoNightBlack";
      };
      wallpaper.default.path = toString config.stylix.image;
      brightness.enable_ddcutil = true;
      idle.behavior = {
        lock = {
          enabled = false;
          action = "lock";
        };
        screen-off = {
          enabled = false;
          action = "screen_off";
        };
        suspend = {
          enabled = false;
          action = "lock_and_suspend";
        };
      };
    };
    customPalettes.TokyoNightBlack = theme.noctaliaPalette;
  };

  systemd.user.services.noctalia = {
    Unit.PartOf = [ "umbriel-session.target" ];
    Install.WantedBy = lib.mkForce [ "umbriel-session.target" ];
  };
}
