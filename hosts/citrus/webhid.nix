{ pkgs, ... }:
let
  webhidUdevRules = pkgs.writeTextFile {
    name = "webhid-udev-rules";
    destination = "/lib/udev/rules.d/70-webhid.rules";
    text = ''
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="1ca6", ATTRS{idProduct}=="3002", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="1ca6", ATTRS{idProduct}=="3007", TAG+="uaccess"

      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c54d", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c09f", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="3367", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="36a7", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="3710", TAG+="uaccess"
    '';
  };
in
{
  services.udev.packages = [ webhidUdevRules ];
}
