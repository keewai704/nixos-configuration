{
  imports = [
    ./home-manager.nix
    ./network.nix
    ./nix.nix
    ./users.nix
  ];

  nixpkgs.config.allowUnfree = true;
  documentation.nixos.enable = false;

  i18n.defaultLocale = "ja_JP.UTF-8";
  time.timeZone = "Asia/Tokyo";

  services.journald.settings.Journal = {
    SystemMaxUse = "512M";
    RuntimeMaxUse = "128M";
  };
}
