{ inputs, ... }:
{
  imports = [
    ./deepseek-web.nix
    ./home-manager.nix
    ./network.nix
    ./nix.nix
    ./users.nix
  ];

  nixpkgs = {
    config.allowUnfree = true;
    overlays = [ (import ../../pkgs { inherit inputs; }) ];
  };
  documentation.nixos.enable = false;
  programs.nix-ld.enable = true;

  i18n.defaultLocale = "ja_JP.UTF-8";
  time.timeZone = "Asia/Tokyo";

  services.journald.settings.Journal = {
    SystemMaxUse = "512M";
    RuntimeMaxUse = "128M";
  };
}
