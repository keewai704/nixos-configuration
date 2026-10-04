{ pkgs, ... }:
{
  services.usbmuxd.enable = true;

  services.udev.packages = [ pkgs.idescriptor ];
  users.groups.idevice = { };
  users.users.keewai.extraGroups = [ "idevice" ];
}
