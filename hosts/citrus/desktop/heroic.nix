{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  directory = "/mnt/data/Games/Heroic";

  prefixDirectory = "${directory}/Prefixes";

  language = "ja";

  theme = "matugen.css";

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
