{
  imports = [
    ../../modules/desktop
    ./apple-device-usb.nix
    ./apple-sharing.nix
    ./audio.nix
    ./boot.nix
    ./display.nix
    ./game-controller.nix
    ./hardware-configuration.nix
    ./input-method.nix
    ./kernel.nix
    ./nvidia.nix
    ./t3code.nix
    ./sunshine.nix
    ./web.nix
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
