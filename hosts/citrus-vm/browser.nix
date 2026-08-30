{ lib, pkgs, ... }:

let
  # Use the current official binary until the pinned nixpkgs package catches up.
  # This only repackages the binary for NixOS; Chromium is not compiled locally.
  braveOriginVersion = "1.94.117";
  braveOrigin =
    if lib.versionAtLeast pkgs.brave-origin.version braveOriginVersion then
      pkgs.brave-origin
    else
      pkgs.brave-origin.overrideAttrs (_: {
        version = braveOriginVersion;
        src = pkgs.fetchurl {
          url = "https://github.com/brave/brave-browser/releases/download/v${braveOriginVersion}/brave-origin_${braveOriginVersion}_amd64.deb";
          hash = "sha256-xY1483jABvhlaCVSh9yDAwrXQ08EoE++wQcJalTVvuY=";
        };
      });

  firefoxDesktop = "firefox.desktop";

  webhidUdevRules = pkgs.writeTextFile {
    name = "webhid-udev-rules";
    destination = "/lib/udev/rules.d/70-webhid.rules";
    text = ''
      # Everglide SU75 Pro WebHID interface from the current SparkLink catalog.
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="1ca6", ATTRS{idProduct}=="3002", TAG+="uaccess"

      # Devices supported by the OpenMouse WebHID control panel. The remaining
      # vendor-wide matches mirror its protocol-based device discovery.
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c54d", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="3367", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="36a7", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="3710", TAG+="uaccess"
    '';
  };
in
{
  environment.systemPackages = [ braveOrigin ];

  programs.firefox.enable = true;

  services.udev.packages = [ webhidUdevRules ];

  home-manager.users.keewai.xdg = {
    configFile."mimeapps.list".force = true;

    desktopEntries = {
      everglide-web-driver = {
        name = "Everglide SU75 Pro Web Driver";
        comment = "Configure the Everglide SU75 Pro over WebHID";
        exec = "${lib.getExe braveOrigin} --new-window https://www.xsyd.top/connect";
        icon = "input-keyboard";
        categories = [ "Settings" ];
        terminal = false;
      };

      openmouse = {
        name = "OpenMouse Control Panel";
        comment = "Configure supported mice over WebHID";
        exec = "${lib.getExe braveOrigin} --new-window https://keewai704.github.io/openmouse/";
        icon = "input-mouse";
        categories = [ "Settings" ];
        terminal = false;
      };
    };

    mimeApps = {
      enable = true;
      defaultApplications = {
        "application/xhtml+xml" = [ firefoxDesktop ];
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
