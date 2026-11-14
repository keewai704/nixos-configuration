{ pkgs, ... }:
{
  home-manager.users.keewai.home.packages = [
    pkgs.pinentry-qt
    pkgs.rbw
  ];
}
