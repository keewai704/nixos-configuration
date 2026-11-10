let
  inherit (import ./settings.nix) hostName;
in
{
  imports = [
    ./boot.nix
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

  services.logind.settings.Login.HandlePowerKey = "suspend";

  systemd.slices.nix.sliceConfig.MemoryHigh = "20G";

  system.stateVersion = "26.05";
}
