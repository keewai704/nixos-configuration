{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  xdg.mime.defaultApplications = {
    "text/html" = "zen-beta.desktop";
    "x-scheme-handler/http" = "zen-beta.desktop";
    "x-scheme-handler/https" = "zen-beta.desktop";
  };

  home-manager.users.keewai =
    { config, ... }:
    {
      imports = [ inputs.zen-browser.homeModules.beta ];

      programs.zen-browser = {
        enable = true;
        policies = {
          RequestedLocales = [
            "ja"
            "en-US"
          ];
          TranslateEnabled = false;
          SearchSuggestEnabled = true;
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
              "e122b5d9-d385-4bf8-9971-e137809097d0"
            ];
          };
          settings = {
            "sine.allow-unsafe-js" = true;
            "zen.glance.enabled" = false;
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
