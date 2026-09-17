{
  config,
  ...
}:

{
  imports = [ ./shell.nix ];

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

    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      extra-substituters = [
        "https://hyprland.cachix.org"
        "https://nyx-cache.chaotic.cx/"
      ];
      extra-trusted-public-keys = [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk="
      ];
    };
  };

  security.sudo.wheelNeedsPassword = false;

  services = {
    journald.settings.Journal = {
      SystemMaxUse = "512M";
      RuntimeMaxUse = "128M";
    };

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
    linger = true;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };
}
