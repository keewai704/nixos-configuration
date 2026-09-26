{
  imports = [
    ../../modules/desktop
    ./apple-device-usb.nix
    ./audio.nix
    ./boot.nix
    ./fingerprint.nix
    ./hardware-configuration.nix
    ./input-method.nix
    ./nvidia.nix
    ./sunshine.nix
    ./webhid.nix
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
