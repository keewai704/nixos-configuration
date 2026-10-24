{
  config,
  inputs,
  lib,
  theme,
  ...
}:
{
  imports = [ inputs.noctalia.homeModules.default ];

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
    customPalettes.TokyoNightBlack.dark = with theme.base16Scheme; {
      mPrimary = "#${base0D}";
      mOnPrimary = "#${base00}";
      mSecondary = "#${base0C}";
      mOnSecondary = "#${base00}";
      mTertiary = "#${base0E}";
      mOnTertiary = "#${base00}";
      mError = "#${base08}";
      mOnError = "#${base00}";
      mSurface = "#${base00}";
      mOnSurface = "#${base05}";
      mSurfaceVariant = "#${base01}";
      mOnSurfaceVariant = "#${base04}";
      mOutline = "#${base02}";
      mShadow = "#${base00}";
      mHover = "#${base02}";
      mOnHover = "#${base05}";
    };
  };

  systemd.user.services.noctalia = {
    Unit.PartOf = [ "umbriel-session.target" ];
    Install.WantedBy = lib.mkForce [ "umbriel-session.target" ];
  };
}
