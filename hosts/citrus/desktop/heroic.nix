{
  impastoPaletteHook,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  directory = "/mnt/data/Games/Heroic";

  prefixDirectory = "${directory}/Prefixes";

  language = "ja";

  theme = "impasto.css";

  themeCss = pkgs.writers.writePython3Bin "heroic-theme" { flakeIgnore = [ "E501" ]; } ''
    import json
    import os
    import sys

    c = json.load(sys.stdin)


    def channels(value):
        value = value.lstrip("#")
        return [int(value[index:index + 2], 16) for index in (0, 2, 4)]


    def mix(start, end, percent):
        start = channels(start)
        end = channels(end)
        return "#" + "".join(f"{round(a + (b - a) * percent / 100):02x}" for a, b in zip(start, end))


    background = c["background"]
    surface = c["surface"]
    surface_hover = c["surfaceHover"]
    border = c["border"]
    text = c["text"]
    muted = c["textMuted"]
    accent = c["accent"]
    accent_hover = c["accentHover"]
    accent_text = c["accentText"]
    red = c["red"]
    green = c["green"]
    yellow = c["yellow"]

    surface_dim = mix(background, surface, 50)
    secondary_container = mix(surface_hover, yellow, 18)
    tertiary_container = mix(surface_hover, green, 18)
    error_container = mix(surface_hover, red, 18)

    css = f"""body.impasto {{
      --accent: {green};
      --accent-overlay: {background};
      --primary: {accent};
      --primary-hover: {accent_hover};
      --navbar-accent: var(--primary);
      --background: {background};
      --body-background: {surface};
      --navbar-background: {surface};
      --background-darker: var(--background);
      --current-background: var(--body-background);
      --navbar-active-background: {surface_hover};
      --gradient-body-background: linear-gradient(90deg, var(--background-darker) -32px, var(--body-background) 64px, var(--body-background) 100%);
      --input-background: {surface};
      --modal-background: {surface};
      --modal-border: {surface_hover};
      --success: {green};
      --success-hover: {tertiary_container};
      --danger: {red};
      --danger-hover: {error_container};
      --text-default: {text};
      --text-title: {text};
      --text-secondary: {muted};
      --text-tertiary: {muted};
      --text-hover: {accent};
      --action-icon: {text};
      --action-icon-hover: {accent};
      --action-icon-active: {accent_hover};
      --icons-background: {surface_hover};
      --icon-disabled: {muted};
      --anticheat-denied: var(--danger);
      --anticheat-broken: var(--accent);
      --anticheat-running: var(--primary);
      --anticheat-supported: var(--success);
      --anticheat-planned: {border};
      --status-success: {green};
      --status-success-hover: {tertiary_container};
      --status-warning: {yellow};
      --status-warning-hover: {secondary_container};
      --status-danger: {red};
      --status-danger-hover: {error_container};
      --status-default: {muted};
      --status-info: {accent};
      --status-denied: {red};
      --brand-primary: {accent};
      --brand-primary-hover: {accent_hover};
      --brand-secondary: {yellow};
      --brand-text-01: {accent_text};
      --brand-text-02: {yellow};
      --neutral-01: {muted};
      --neutral-02: {surface_dim};
      --neutral-03: {surface};
      --neutral-04: {muted};
      --neutral-05: {muted};
      --neutral-06: {text};
      --neutral-07: {surface_hover};
      --neutral-08: {border};
      --background-light: {surface};
      --background-lighter: {surface_hover};
      --background-darker-80: {background}cc;
      --eighty-percent-black: {background}cc;
      --primary-button: {accent};
      --primary-active: {accent_hover};
      --secondary-button: {yellow};
      --success-button: {green};
      --tertiary-button: {yellow};
      --install-button: {accent};
      --disabled-button: {border};
      --disabled-button-overlay: {surface_hover};
      --navbar-active: {accent_hover};
      --navbar-inactive: {muted};
      --gamecard-title-color: {muted}cc;
      --osk-background: {surface};
      --osk-button-background: {surface};
      --osk-button-border: {border};
      --text-log: {muted};
      --tour-popup-background: {surface};
      --tour-popup-title: {text};
      --tour-popup-skip-color: {muted};
      --tour-popup-skip-color-hover: {accent};
      --tour-bullet-active: {accent};
      --tour-bullet-inactive: {border};
    }}
    """

    path = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "heroic", "themes", "${theme}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(css)
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
    imports = [ (impastoPaletteHook "heroic" "heroic/themes/${theme}" themeCss) ];

    home.packages = [ pkgs.local.heroic ];

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
