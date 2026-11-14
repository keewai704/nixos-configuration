{ pkgs, ... }:
{
  home-manager.users.keewai = {
    home.packages = [ pkgs.local.heroic ];

    xdg.dataFile = {
      "applications/com.heroicgameslauncher.hgl.desktop" = {
        source = "${pkgs.local.heroic}/share/applications/com.heroicgameslauncher.hgl.desktop";
      };
      "icons/hicolor/scalable/apps/com.heroicgameslauncher.hgl.svg" = {
        source = "${pkgs.local.heroic}/share/icons/hicolor/scalable/apps/com.heroicgameslauncher.hgl.svg";
      };
    };
  };
}
