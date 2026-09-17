{ pkgs, ... }:
{
  boot = {
    loader = {
      efi.canTouchEfiVariables = true;
      limine = {
        enable = true;
        maxGenerations = 10;
        style = {
          interface.resolution = "5120x2160";
          graphicalTerminal.font.scale = "2x2";
          wallpapers = [
            (pkgs.fetchurl {
              url = "https://raw.githubusercontent.com/CachyOS/cachyos-wallpapers/91875ae10c410e7e2b81f8af0ef44e7f7aea114d/usr/share/wallpapers/cachyos-wallpapers/limine-splash.png";
              hash = "sha256-+S8J+XKbIpfNKbN76/yBEpbYx3FUiXQ5Ut5LmBeFAt8=";
            })
          ];
        };
      };
    };
    kernelPackages = pkgs.linuxPackages_cachyos;
  };
}
