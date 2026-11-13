let
  inherit (import ./settings.nix) hostName;
in
{
  imports = [
    ./boot.nix
    ./bootvine.nix
    ./desktop
    ./faster-whisper.nix
    ./graphics.nix
    ./hardware-configuration.nix
    ./services
  ];

  networking = {
    inherit hostName;
    hostId = "175be74a";
  };

  hardware.cpu.amd.ryzen-smu.enable = true;

  services.logind.settings.Login.HandlePowerKey = "suspend";

  systemd.settings.Manager.RuntimeWatchdogSec = "30s";

  systemd.slices.nix.sliceConfig.MemoryHigh = "20G";

  system.stateVersion = "26.05";
}
