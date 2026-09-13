{ pkgs, ... }:
{
  imports = [ ./shared ];

  home.packages = [
    pkgs.git
    pkgs.ripgrep
  ];
}
