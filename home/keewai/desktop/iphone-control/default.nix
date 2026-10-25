{ lib, pkgs, ... }:
let
  mobileDeviceCommand = import ../../common/apple-device-command.nix { inherit lib pkgs; };
  control = mobileDeviceCommand {
    name = "iphone-control";
    command = "python ${./control.py} --helper-dir ${../../../../skills/apple-device-usb/scripts} --browser ${lib.getExe pkgs.local.helium}";
    runtimeInputs = [
      pkgs.ffmpeg-headless
      pkgs.iproute2
      pkgs.zenity
    ];
  };
in
{
  home.packages = [ control ];

  xdg.desktopEntries.iphone-control = {
    name = "iPhone / iPad Control";
    comment = "View and control a USB-connected Apple device";
    icon = "phone";
    exec = lib.getExe control;
    categories = [ "Utility" ];
    terminal = false;
  };
}
