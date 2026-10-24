{ lib, ... }:
{
  networking.networkmanager.enable = lib.mkDefault true;
  hardware.bluetooth.enable = lib.mkDefault true;
  hardware.i2c.enable = true;
  security.rtkit.enable = true;
  services = {
    upower.enable = true;
    power-profiles-daemon.enable = lib.mkDefault true;
    pipewire = {
      enable = lib.mkDefault true;
      pulse.enable = lib.mkDefault true;
    };
  };
}
