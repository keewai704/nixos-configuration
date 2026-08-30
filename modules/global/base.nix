{ pkgs, ... }:

{
  time.timeZone = "Asia/Tokyo";

  i18n.defaultLocale = "ja_JP.UTF-8";

  users.users.keewai = {
    isNormalUser = true;
    description = "keewai";
    extraGroups = [ "wheel" ];
  };

  environment.systemPackages = with pkgs; [
    git
    ripgrep
  ];

  security.sudo.wheelNeedsPassword = false;

  services.journald.extraConfig = ''
    SystemMaxUse=512M
    RuntimeMaxUse=128M
  '';

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };

    optimise = {
      automatic = true;
    };

    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };
}
