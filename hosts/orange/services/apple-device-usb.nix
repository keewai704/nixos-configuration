{ ... }:
{
  services.usbmuxd.enable = true;
  orange.healthMonitor.units = [ "usbmuxd.service" ];
}
