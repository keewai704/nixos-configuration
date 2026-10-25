{ pkgs, ... }:
let
  theme = import ../../themes/tokyo-night-black { inherit pkgs; };
in
{
  imports = [
    ./bitwarden.nix
    ./umbriel.nix
    ./noctalia.nix
    ./scheduler.nix
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
  };
}
