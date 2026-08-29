{
  lib,
  pkgs,
  ...
}:

let
  chatgptDesktop = pkgs.callPackage ../pkgs/chatgpt-desktop/package.nix { };
in
{
  imports = [ ../modules/chatgpt-desktop-extensions.nix ];

  nixpkgs.config.allowUnfreePredicate = package: lib.getName package == "chatgpt-desktop";

  environment.systemPackages = [ chatgptDesktop ];

  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        gtk-theme = "Adwaita-dark";
      };
      lockAll = true;
    }
  ];

  services.gnome.at-spi2-core.enable = true;
}
