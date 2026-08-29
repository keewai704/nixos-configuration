{
  lib,
  pkgs,
  ...
}:

let
  chatgptDesktop = pkgs.callPackage ../pkgs/chatgpt-desktop/package.nix { };
in
{
  nixpkgs.config.allowUnfreePredicate = package: lib.getName package == "chatgpt-desktop";

  environment.systemPackages = [ chatgptDesktop ];

  services.gnome.at-spi2-core.enable = true;
}
