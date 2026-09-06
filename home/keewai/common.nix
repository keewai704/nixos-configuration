{ pkgs, ... }:
{
  home.packages = [
    pkgs.git
    pkgs.ripgrep
  ];
}
