{
  osConfig,
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
  # The pinned upstream exports a mixed NixOS module. Reuse its package and
  # profile activation directly, translating only the browser option boundary.
  upstream = inputs.my-firefox-nix.nixosModules.default { inherit lib pkgs; };
  firefox = upstream.programs.firefox;
in
assert lib.assertMsg (
  builtins.attrNames firefox == [
    "autoConfig"
    "enable"
    "languagePacks"
    "package"
    "preferences"
  ]
) "my-firefox-nix changed its options; review the Home Manager adapter before updating.";
{
  imports = [ upstream.home-manager.users.keewai ];
  home.packages = [
    braveOrigin
    pkgs.pywalfox-native
  ];
  programs.firefox = {
    enable = true;
    package = firefox.package.override (old: {
      extraPrefsFiles = (old.extraPrefsFiles or [ ]) ++ [
        (pkgs.writeText "firefox-autoconfig.js" firefox.autoConfig)
      ];
    });
    inherit (firefox) languagePacks;
    nativeMessagingHosts = [ pywalfoxManifest ];
    policies = {
      DisableAppUpdate = true;
      Preferences = builtins.mapAttrs (_: value: {
        Value = value;
        Status = "locked";
      }) firefox.preferences;
    };
  };

  xdg = {
    cacheFile."wal/colors.json".text = builtins.toJSON {
      wallpaper = osConfig.stylix.image;
      alpha = "100";
      special = with osConfig.lib.stylix.colors; {
        background = "#${base00}";
        foreground = "#${base05}";
        cursor = "#${base05}";
      };
      colors = builtins.listToAttrs (
        lib.imap0 (index: color: lib.nameValuePair "color${toString index}" "#${color}") (
          with osConfig.lib.stylix.colors;
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
