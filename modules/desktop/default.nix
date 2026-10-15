{ pkgs, ... }:
let
  theme = import ../../themes/tokyo-night-black { inherit pkgs; };
in
{
  imports = [
    ./bitwarden.nix
    ./cpak.nix
    ./hypr-brightness.nix
    ./impasto.nix
    ./hyprland.nix
    ./input-method.nix
    ./steam.nix
    ./stylix.nix
    ./tailscale-operator.nix
  ];

  _module.args = { inherit theme; };

  home-manager.users.keewai = {
    imports = [ ../../home/keewai/desktop ];
    _module.args = { inherit theme; };
  };

  programs.dconf.enable = true;
  programs.nix-ld.enable = true;

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
