{ pkgs, ... }:
{
  imports = [
    ./bitwarden.nix
    ./cpak.nix
    ./hypr-brightness.nix
    ./island.nix
    ./hyprland.nix
    ./input-method.nix
    ./steam.nix
    ./stylix.nix
    ./deepseek-harness.nix
  ];

  home-manager.users.keewai.imports = [ ../../home/keewai/desktop ];

  programs.dconf.enable = true;

  services = {
    gnome.at-spi2-core.enable = true;
    gnome.gnome-keyring.enable = true;
    gvfs.enable = true;
    tumbler.enable = true;
    scx = {
      enable = true;
      package = pkgs.scx.rustscheds;
      scheduler = "scx_lavd";
    };
  };
}
