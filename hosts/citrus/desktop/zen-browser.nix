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
          sine.enable = true;
          settings = {
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
