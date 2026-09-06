{
  config,
  ...
}:

{
  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 10;
    };
    efi.canTouchEfiVariables = true;
  };

  i18n.defaultLocale = "ja_JP.UTF-8";
  time.timeZone = "Asia/Tokyo";

  networking = {
    networkmanager.enable = true;
    firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
  };

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };

    optimise.automatic = true;

    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  services = {
    journald.extraConfig = ''
      SystemMaxUse=512M
      RuntimeMaxUse=128M
    '';

    openssh = {
      enable = true;
      openFirewall = false;
    };

    tailscale = {
      enable = true;
      extraSetFlags = [
        "--hostname=${config.networking.hostName}"
        "--ssh"
      ];
    };
  };

  users.users.keewai = {
    isNormalUser = true;
    description = "keewai";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };
}
