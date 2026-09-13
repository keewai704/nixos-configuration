{
  config,
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    ../../modules/desktop.nix
    ./bitwarden.nix
  ];

  programs = {
    gamescope = {
      enable = true;
      enableWsi = true;
    };

    steam = {
      enable = true;
      package = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.millennium-steam;
      fontPackages = config.stylix.fonts.packages ++ [ pkgs.noto-fonts ] ++ config.fonts.packages;
      extraPackages = [ pkgs.gamescope ];
      extraCompatPackages = [ pkgs.proton-ge-bin ];
    };
  };

  services = {
    gnome.at-spi2-core.enable = true;
    gnome.gnome-keyring.enable = true;
    gvfs.enable = true;
    tumbler.enable = true;
  };
}
