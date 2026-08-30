{ pkgs, ... }:

let
  firefoxDesktop = "firefox.desktop";

  webhidUdevRules = pkgs.writeTextFile {
    name = "webhid-udev-rules";
    destination = "/lib/udev/rules.d/70-webhid.rules";
    text = ''
      # SparkLink keyboard controllers used by Everglide web drivers.
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="1ca6", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="38a6", TAG+="uaccess"

      # Vendors supported by the OpenMouse WebHID control panel.
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="046d", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="3367", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="36a7", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="3710", TAG+="uaccess"
    '';
  };
in
{
  environment.systemPackages = [ pkgs.brave-origin ];

  programs.firefox.enable = true;

  services.udev.packages = [ webhidUdevRules ];

  home-manager.users.keewai.xdg = {
    configFile."mimeapps.list".force = true;

    mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = [ firefoxDesktop ];
        "x-scheme-handler/about" = [ firefoxDesktop ];
        "x-scheme-handler/codex" = [ "chatgpt.desktop" ];
        "x-scheme-handler/http" = [ firefoxDesktop ];
        "x-scheme-handler/https" = [ firefoxDesktop ];
        "x-scheme-handler/unknown" = [ firefoxDesktop ];
      };
    };
  };
}
