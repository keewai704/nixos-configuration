{
  imports = [
    ./audio.nix
    ./boot.nix
    ./webhid.nix
    ./desktop.nix
    ./hypr-island.nix
    ./fingerprint.nix
    ./hardware-configuration.nix
    ./hyprland.nix
    ./input-method-shortcut.nix
    ./apple-device-usb.nix
    ./nvidia.nix
    ./paseo-tailscale.nix
    ./pi-web-tailscale.nix
    ./stylix.nix
  ];

  networking.hostName = "citrus";
  system.stateVersion = "26.05";

  nix = {
    settings = {
      max-jobs = 2;
      cores = 6;
    };
    daemonIOSchedClass = "idle";
  };
  systemd.services.nix-daemon.serviceConfig.Nice = 10;

  users.users.keewai.extraGroups = [
    "audio"
    "i2c"
    "video"
  ];
}
