{ pkgs, ... }:
{
  home-manager.users.keewai = {
    home.packages = [ pkgs.heroic ];

    xdg.dataFile = {
      "applications/com.heroicgameslauncher.hgl.desktop" = {
        source = "${pkgs.heroic}/share/applications/com.heroicgameslauncher.hgl.desktop";
      };
      "icons/hicolor/scalable/apps/com.heroicgameslauncher.hgl.svg" = {
        source = "${pkgs.heroic}/share/icons/hicolor/scalable/apps/com.heroicgameslauncher.hgl.svg";
      };
    };
  };
}
