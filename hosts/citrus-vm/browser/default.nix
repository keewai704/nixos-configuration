{
  config,
  lib,
  pkgs,
  ...
}:

let
  theme = import ../theme.nix {
    inherit pkgs;
    colors = config.lib.stylix.colors;
  };

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

  firefoxDesktop = "firefox.desktop";

  pywalfox = pkgs.pywalfox-native;
  pywalfoxManifest = pkgs.writeTextDir "lib/mozilla/native-messaging-hosts/pywalfox.json" (
    builtins.toJSON {
      name = "pywalfox";
      description = "Automatically theme Firefox using the Nix-managed Pywal palette";
      path = lib.getExe pywalfox;
      type = "stdio";
      allowed_extensions = [ "pywalfox@frewacom.org" ];
    }
  );
  pywalfoxPalette = with theme.palette; [
    background
    red
    green
    yellow
    blue
    magenta
    cyan
    foreground
    comment
    red
    green
    yellow
    blue
    magenta
    cyan
    config.lib.stylix.colors.base07
  ];
  pywalfoxColors = builtins.listToAttrs (
    lib.imap0 (index: color: lib.nameValuePair "color${toString index}" "#${color}") pywalfoxPalette
  );
  pywalfoxTheme = builtins.toJSON {
    wallpaper = toString theme.wallpaper;
    alpha = "100";
    special = {
      background = "#${theme.semantic.windowBackground}";
      foreground = "#${theme.semantic.text}";
      cursor = "#${theme.semantic.text}";
    };
    colors = pywalfoxColors;
  };

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
  imports = [ ./sine.nix ];

  environment.systemPackages = [
    braveOrigin
    pywalfox
  ];

  programs.firefox.nativeMessagingHosts.packages = [ pywalfoxManifest ];

  services.udev.packages = [ webhidUdevRules ];

  home-manager.users.keewai.xdg = {
    cacheFile."wal/colors.json".text = pywalfoxTheme;
    configFile."mimeapps.list".force = true;

    desktopEntries = {
      everglide-web-driver = {
        name = "Everglide SU75 Pro Webドライバー";
        comment = "Everglide SU75 ProをWebHIDで設定";
        exec = "${lib.getExe braveOrigin} --new-window https://www.xsyd.top/connect";
        icon = "input-keyboard";
        categories = [ "Settings" ];
        terminal = false;
      };

      openmouse = {
        name = "OpenMouse コントロールパネル";
        comment = "対応マウスをWebHIDで設定";
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
