{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  directory = "/mnt/data/Games/Heroic";

  prefixDirectory = "${directory}/Prefixes";

  language = "ja";

  theme = "stylix.css";

  color = import ./material-colors.nix config.lib.stylix.colors.withHashtag;

  themeCss = with color; ''
    body.stylix {
      --accent: ${tertiary};
      --accent-overlay: ${inverse-primary};
      --primary: ${primary};
      --primary-hover: ${primary-container};
      --navbar-accent: var(--primary);
      --background: ${background};
      --body-background: ${surface};
      --navbar-background: ${surface-container};
      --background-darker: var(--background);
      --current-background: var(--body-background);
      --navbar-active-background: ${surface-container-high};
      --gradient-body-background: linear-gradient(90deg, var(--background-darker) -32px, var(--body-background) 64px, var(--body-background) 100%);
      --input-background: ${surface-container};
      --modal-background: ${surface};
      --modal-border: ${surface-container-high};
      --success: ${tertiary};
      --success-hover: ${tertiary-container};
      --danger: ${error};
      --danger-hover: ${error-container};
      --text-default: ${on-surface};
      --text-title: ${on-surface};
      --text-secondary: ${on-surface-variant};
      --text-tertiary: ${outline};
      --text-hover: ${primary};
      --action-icon: ${on-surface};
      --action-icon-hover: ${primary};
      --action-icon-active: ${primary-container};
      --icons-background: ${surface-container-high};
      --icon-disabled: ${on-surface-variant};
      --anticheat-denied: var(--danger);
      --anticheat-broken: var(--accent);
      --anticheat-running: var(--primary);
      --anticheat-supported: var(--success);
      --anticheat-planned: ${outline};
      --status-success: ${tertiary};
      --status-success-hover: ${tertiary-container};
      --status-warning: ${secondary};
      --status-warning-hover: ${secondary-container};
      --status-danger: ${error};
      --status-danger-hover: ${error-container};
      --status-default: ${on-surface-variant};
      --status-info: ${primary};
      --status-denied: ${error};
      --brand-primary: ${primary};
      --brand-primary-hover: ${primary-container};
      --brand-secondary: ${secondary};
      --brand-text-01: ${on-primary};
      --brand-text-02: ${on-secondary-container};
      --neutral-01: ${outline};
      --neutral-02: ${surface-dim};
      --neutral-03: ${surface-container-low};
      --neutral-04: ${on-surface-variant};
      --neutral-05: ${outline};
      --neutral-06: ${on-surface};
      --neutral-07: ${surface-container-high};
      --neutral-08: ${surface-container-highest};
      --background-light: ${surface-container-low};
      --background-lighter: ${surface-container-high};
      --background-darker-80: ${scrim}cc;
      --eighty-percent-black: ${scrim}cc;
      --primary-button: ${primary};
      --primary-active: ${primary-container};
      --secondary-button: ${secondary};
      --success-button: ${tertiary};
      --tertiary-button: ${secondary};
      --install-button: ${primary};
      --disabled-button: ${outline-variant};
      --disabled-button-overlay: ${surface-container-high};
      --navbar-active: ${primary-container};
      --navbar-inactive: ${on-surface-variant};
      --gamecard-title-color: ${on-surface-variant}cc;
      --osk-background: ${surface};
      --osk-button-background: ${surface-container};
      --osk-button-border: ${outline-variant};
      --text-log: ${on-surface-variant};
      --tour-popup-background: ${surface-container};
      --tour-popup-title: ${on-surface};
      --tour-popup-skip-color: ${on-surface-variant};
      --tour-popup-skip-color-hover: ${primary};
      --tour-bullet-active: ${primary};
      --tour-bullet-inactive: ${outline-variant};
    }
  '';

  settings = {
    defaultInstallPath = directory;
    defaultWinePrefix = prefixDirectory;
    defaultWinePrefixDir = prefixDirectory;
    inherit language;
    winePrefix = "${prefixDirectory}/shared";
  };
in
{
  home-manager.users.keewai = {
    home.packages = [ pkgs.local.heroic ];

    xdg.configFile."heroic/themes/${theme}".text = themeCss;

    xdg.dataFile = {
      "applications/com.heroicgameslauncher.hgl.desktop" = {
        source = "${pkgs.local.heroic}/share/applications/com.heroicgameslauncher.hgl.desktop";
      };
      "icons/hicolor/scalable/apps/com.heroicgameslauncher.hgl.svg" = {
        source = "${pkgs.local.heroic}/share/icons/hicolor/scalable/apps/com.heroicgameslauncher.hgl.svg";
      };
    };

    home.activation.heroicSettings = inputs.home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      config="''${XDG_CONFIG_HOME:-$HOME/.config}/heroic/config.json"
      store="''${XDG_CONFIG_HOME:-$HOME/.config}/heroic/store/config.json"
      themes="''${XDG_CONFIG_HOME:-$HOME/.config}/heroic/themes"

      run mkdir -p ${directory} ${prefixDirectory} "$themes" "$(dirname "$config")" "$(dirname "$store")"

      [ -s "$config" ] || echo '{}' > "$config"
      merged="$(mktemp "$config.XXXXXX")"
      ${lib.getExe pkgs.jq} --argjson settings ${lib.escapeShellArg (builtins.toJSON settings)} \
        --arg themes "$themes" \
        '.defaultSettings = ((.defaultSettings // {}) + $settings)
          | .defaultSettings.customThemesPath = $themes
          | .version = (.version // "v0")' \
        "$config" > "$merged"
      run mv "$merged" "$config"

      [ -s "$store" ] || echo '{}' > "$store"
      merged="$(mktemp "$store.XXXXXX")"
      ${lib.getExe pkgs.jq} --arg language ${lib.escapeShellArg language} --arg theme ${lib.escapeShellArg theme} \
        '.language = $language
          | .theme = $theme
          | if has("settings") then .settings.language = $language else . end' \
        "$store" > "$merged"
      run mv "$merged" "$store"
    '';
  };
}
