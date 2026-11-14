{
  impastoPaletteHook,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  pywalfox = lib.getExe pkgs.pywalfox-native;

  cache = "impasto/pywalfox";

  host = pkgs.writeShellScript "pywalfox-host" ''
    export XDG_CACHE_HOME="''${XDG_CONFIG_HOME:-$HOME/.config}/${cache}"
    exec ${pywalfox} start
  '';

  colors = pkgs.writers.writePython3Bin "pywalfox-colors" { flakeIgnore = [ "E501" ]; } ''
    import json
    import os
    import subprocess
    import sys

    c = json.load(sys.stdin)
    order = (
        "background", "red", "green", "accent",
        "blue", "accentHover", "textMuted", "surface",
        "border", "red", "accent", "yellow",
        "blue", "accentHover", "textMuted", "text",
    )
    home = os.path.expanduser("~")
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config")
    state = os.environ.get("XDG_STATE_HOME") or os.path.join(home, ".local", "state")
    data = {
        "wallpaper": os.path.join(state, "quickshell", "current-wallpaper"),
        "alpha": "100",
        "colors": {f"color{index}": c[key] for index, key in enumerate(order)},
    }

    path = os.path.join(config, "${cache}", "wal", "colors.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
    os.replace(path + ".tmp", path)

    subprocess.run(["${pywalfox}", "update"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
  '';
in
{
  xdg.mime.defaultApplications = {
    "text/html" = "zen-beta.desktop";
    "x-scheme-handler/http" = "zen-beta.desktop";
    "x-scheme-handler/https" = "zen-beta.desktop";
  };

  home-manager.users.keewai =
    { config, ... }:
    {
      imports = [
        inputs.zen-browser.homeModules.beta
        (impastoPaletteHook "zen" "${cache}/wal/colors.json" colors)
      ];

      stylix.targets.zen-browser.enable = false;

      home.file.".mozilla/native-messaging-hosts/pywalfox.json".text = builtins.toJSON {
        name = "pywalfox";
        description = "Pywalfox native messaging host";
        path = "${host}";
        type = "stdio";
        allowed_extensions = [ "pywalfox@frewacom.org" ];
      };

      programs.zen-browser = {
        enable = true;
        policies = {
          RequestedLocales = [
            "ja"
            "en-US"
          ];
          TranslateEnabled = false;
          SearchSuggestEnabled = true;
          ExtensionSettings."pywalfox@frewacom.org" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi";
          };
          Preferences =
            lib.mapAttrs
              (_: Value: {
                inherit Value;
                Status = "default";
              })
              {
                "intl.accept_languages" = "ja,en-US,en";
                "layout.spellcheckDefault" = 0;
                "signon.firefoxRelay.feature" = "disabled";
                "dom.security.https_only_mode" = true;
                "browser.urlbar.suggest.searches" = true;
              };
        };
        profiles.default = {
          id = 0;
          name = "Default Profile";
          path = "qpmgf4mu.Default Profile";
          isDefault = true;
          sine = {
            enable = true;
            mods = [
              "58649066-2b6f-4a5b-af6d-c3d21d16fc00"
              "599a1599-e6ab-4749-ab22-de533860de2c"
              "642854b5-88b4-4c40-b256-e035532109df"
              "906c6915-5677-48ff-9bfc-096a02a72379"
              "a5f6a231-e3c8-4ce8-8a8e-3e93efd6adec"
              "a6335949-4465-4b71-926c-4a52d34bc9c0"
              "ad97bb70-0066-4e42-9b5f-173a5e42c6fc"
              "auto-pip-setting"
              "c01d3e22-1cee-45c1-a25e-53c0f180eea8"
              "context-menu-icons"
              "e122b5d9-d385-4bf8-9971-e137809097d0"
            ];
          };
          userChrome = builtins.readFile "${inputs.pywal-zen}/chrome/pywal-zen.css";
          settings = {
            "zen.theme.disable-lightweight" = false;
            "sine.allow-unsafe-js" = true;
            "browser.tabs.allow_transparent_browser" = true;
            "zen.widget.linux.transparency" = true;
            "zen.glance.enabled" = false;
            "zen.urlbar.single-toolbar-show-copy-url" = false;
            "font.default.ja" = "sans-serif";
            "font.default.x-western" = "sans-serif";
            "font.name.sans-serif.ja" = "Noto Sans CJK JP";
            "font.name.sans-serif.x-western" = "Noto Sans CJK JP";
          };
        };
      };

      programs.gh.settings.browser = lib.mkForce "${lib.getExe' pkgs.systemd "systemd-run"} --user --collect --quiet ${lib.getExe config.programs.zen-browser.finalPackage}";
    };
}
