{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./camofox.nix
    ./media-services.nix
  ];

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 10;
      };
      efi.canTouchEfiVariables = true;
    };
  };

  networking = {
    hostName = "orange";
    networkmanager = {
      enable = true;
      dispatcherScripts = [
        {
          source = pkgs.writeShellScript "tailscale-udp-gro-forwarding" ''
            if [ "$1" = "enp2s0" ] && [ "$2" = "up" ]; then
              ${pkgs.ethtool}/bin/ethtool -K "$1" \
                rx-udp-gro-forwarding on \
                rx-gro-list off
            fi
          '';
        }
      ];
    };

    firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
  };

  time.timeZone = "Asia/Tokyo";

  i18n = {
    defaultLocale = "ja_JP.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "ja_JP.UTF-8";
      LC_IDENTIFICATION = "ja_JP.UTF-8";
      LC_MEASUREMENT = "ja_JP.UTF-8";
      LC_MONETARY = "ja_JP.UTF-8";
      LC_NAME = "ja_JP.UTF-8";
      LC_NUMERIC = "ja_JP.UTF-8";
      LC_PAPER = "ja_JP.UTF-8";
      LC_TELEPHONE = "ja_JP.UTF-8";
      LC_TIME = "ja_JP.UTF-8";
    };
  };

  services = {
    xserver.xkb = {
      layout = "us";
      variant = "";
    };

    openssh = {
      enable = true;
      openFirewall = false;
    };

    tailscale = {
      enable = true;
      useRoutingFeatures = "server";
      extraSetFlags = [
        "--ssh"
        "--advertise-exit-node"
      ];
    };

    journald.extraConfig = ''
      SystemMaxUse=512M
      RuntimeMaxUse=128M
    '';
  };

  users.users.keewai = {
    isNormalUser = true;
    description = "keewai";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  environment.systemPackages = [ pkgs.ripgrep ];

  security.sudo.wheelNeedsPassword = false;

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
    optimise = {
      automatic = true;
      dates = [ "03:45" ];
    };
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      min-free = 5 * 1024 * 1024 * 1024;
      max-free = 10 * 1024 * 1024 * 1024;
    };
  };

  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "26.05";
}
