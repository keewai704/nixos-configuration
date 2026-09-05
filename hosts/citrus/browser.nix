{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  # Use the current official binary until the pinned nixpkgs package catches up.
  # This only repackages the binary for NixOS; Chromium is not compiled locally.
  braveOriginVersion = "1.94.117";
  braveOriginBase = pkgs.brave-origin.override {
    commandLineArgs = "--lang=ja --accept-lang=ja-JP,ja,en-US,en";
  };
  braveOriginCurrent =
    if lib.versionAtLeast braveOriginBase.version braveOriginVersion then
      braveOriginBase
    else
      braveOriginBase.overrideAttrs (_: {
        version = braveOriginVersion;
        src = pkgs.fetchurl {
          url = "https://github.com/brave/brave-browser/releases/download/v${braveOriginVersion}/brave-origin_${braveOriginVersion}_amd64.deb";
          hash = "sha256-xY1483jABvhlaCVSh9yDAwrXQ08EoE++wQcJalTVvuY=";
        };
      });
  braveOrigin = braveOriginCurrent.overrideAttrs (previous: {
    preFixup = (previous.preFixup or "") + ''
      gappsWrapperArgs+=(
        --set LANG ja_JP.UTF-8
        --set LANGUAGE ja_JP:ja
      )
    '';
  });

  pywalfoxManifest = pkgs.writeTextDir "lib/mozilla/native-messaging-hosts/pywalfox.json" (
    builtins.toJSON {
      name = "pywalfox";
      description = "Automatically theme Firefox using the Nix-managed Pywal palette";
      path = lib.getExe pkgs.pywalfox-native;
      type = "stdio";
      allowed_extensions = [ "pywalfox@frewacom.org" ];
    }
  );
  webhidUdevRules = pkgs.writeTextFile {
    name = "webhid-udev-rules";
    destination = "/lib/udev/rules.d/70-webhid.rules";
    text = ''
      # Everglide SU75 Pro and the connected SU75 Ultra (TwinStar).
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="1ca6", ATTRS{idProduct}=="3002", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="1ca6", ATTRS{idProduct}=="3007", TAG+="uaccess"

      # Devices supported by the OpenMouse WebHID control panel. The remaining
      # vendor-wide matches mirror its protocol-based device discovery.
      # Logitech LIGHTSPEED receiver (including PRO X 2c) and wired SUPERLIGHT 2c.
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c54d", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c09f", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="3367", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="36a7", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="3710", TAG+="uaccess"
    '';
  };
in
{
  imports = [ inputs.browser-config.nixosModules.default ];

  environment.systemPackages = [
    braveOrigin
    pkgs.pywalfox-native
  ];

  programs.firefox.nativeMessagingHosts.packages = [ pywalfoxManifest ];

  services.udev.packages = [ webhidUdevRules ];

  home-manager.users.keewai.xdg = {
    cacheFile."wal/colors.json".text = builtins.toJSON {
      wallpaper = config.stylix.image;
      alpha = "100";
      special = with config.lib.stylix.colors; {
        background = "#${base00}";
        foreground = "#${base05}";
        cursor = "#${base05}";
      };
      colors = builtins.listToAttrs (
        lib.imap0 (index: color: lib.nameValuePair "color${toString index}" "#${color}") (
          with config.lib.stylix.colors;
          [
            base00
            base08
            base0B
            base0A
            base0D
            base0E
            base0C
            base05
            base03
            base08
            base0B
            base0A
            base0D
            base0E
            base0C
            base07
          ]
        )
      );
    };
    configFile."mimeapps.list".force = true;

    desktopEntries = {
      everglide-web-driver = {
        name = "TwinStar Webドライバー";
        comment = "EverglideキーボードをTwinStar WebHIDで設定";
        exec = "${lib.getExe braveOrigin} --app=https://v2-dev.xsyd.top/";
        icon = "input-keyboard";
        categories = [ "Settings" ];
        terminal = false;
      };

      openmouse = {
        name = "OpenMouse コントロールパネル";
        comment = "G PRO X SUPERLIGHT 2cなどの対応マウスをWebHIDで設定";
        exec = "${lib.getExe braveOrigin} --app=https://control.openmouse.app/";
        icon = "input-mouse";
        categories = [ "Settings" ];
        terminal = false;
      };
    };

    mimeApps = {
      enable = true;
      defaultApplications = {
        "application/xhtml+xml" = [ "firefox.desktop" ];
        "text/html" = [ "firefox.desktop" ];
        "x-scheme-handler/about" = [ "firefox.desktop" ];
        "x-scheme-handler/http" = [ "firefox.desktop" ];
        "x-scheme-handler/https" = [ "firefox.desktop" ];
        "x-scheme-handler/unknown" = [ "firefox.desktop" ];
        "x-scheme-handler/codex" = [ "chatgpt.desktop" ];
      };
    };
  };
}
