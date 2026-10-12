{
  config,
  lib,
  ...
}:
let
  state = "${config.xdg.stateHome}/quickshell";
  fonts = config.stylix.fonts;
  qtSettings = {
    Appearance = {
      style = "Fusion";
      icon_theme = config.gtk.iconTheme.name;
      custom_palette = true;
      color_scheme_path = "${state}/qt-palette.conf";
      standard_dialogs = "xdgdesktopportal";
    };
    Fonts = {
      fixed = ''"${fonts.monospace.name},${toString fonts.sizes.applications}"'';
      general = ''"${fonts.sansSerif.name},${toString fonts.sizes.applications}"'';
    };
  };
in
{
  config = lib.mkIf config.programs.island.enable {
    stylix.targets.gtk.extraCss = lib.mkAfter ''
      @import url("file://${state}/gtk-colors.css");
    '';

    stylix.targets.qt.enable = lib.mkForce false;
    qt = {
      enable = true;
      platformTheme.name = "qtct";
      style.name = "Fusion";
      qt5ctSettings = qtSettings;
      qt6ctSettings = qtSettings;
    };

    programs.kitty = {
      settings = {
        allow_remote_control = "socket-only";
        listen_on = "unix:\${XDG_RUNTIME_DIR}/kitty.sock";
      };
      extraConfig = lib.mkAfter ''
        include ${state}/kitty-palette.conf
        include ${state}/kitty-font.conf
      '';
    };
  };
}
