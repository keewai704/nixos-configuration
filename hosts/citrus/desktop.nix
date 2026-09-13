{
  imports = [
    ../../modules/desktop.nix
    ./bitwarden.nix
    ./steam.nix
  ];

  services = {
    gnome.at-spi2-core.enable = true;
    gnome.gnome-keyring.enable = true;
    gvfs.enable = true;
    tumbler.enable = true;
  };
}
