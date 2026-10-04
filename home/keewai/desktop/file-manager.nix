{ pkgs, ... }:
let
  thunar = pkgs.thunar.override {
    thunarPlugins = [
      pkgs.thunar-archive-plugin
      pkgs.thunar-volman
    ];
  };
in
{
  home.packages = [
    pkgs.xarchiver
    thunar
    pkgs.xfconf
  ];
  systemd.user.packages = [ pkgs.xfconf ];

  xdg = {
    mimeApps.defaultApplications."inode/directory" = [ "thunar.desktop" ];
    userDirs = {
      enable = true;
      createDirectories = true;
    };
    configFile = {
      "systemd/user/thunar.service".source = "${thunar}/lib/systemd/user/thunar.service";
      "user-dirs.dirs".force = true;
    };
  };
}
