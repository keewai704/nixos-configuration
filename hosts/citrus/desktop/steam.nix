{
  config,
  impastoPaletteHook,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  theme = "SpaceTheme";

  quickCssWatcher = "quick-css-watcher";

  plugins =
    lib.mapAttrs' (_: source: {
      inherit ((lib.importJSON "${source}/plugin.json")) name;
      value = source;
    }) (lib.filterAttrs (name: _: lib.hasPrefix "millennium-plugin-" name) inputs)
    // {
      ${quickCssWatcher} = pkgs.symlinkJoin {
        name = "millennium-${quickCssWatcher}";
        paths = [
          (pkgs.writeTextDir "plugin.json" (
            builtins.toJSON {
              name = quickCssWatcher;
              common_name = "Quick CSS Watcher";
              description = "Reloads quick.css whenever the file changes.";
              useBackend = false;
            }
          ))
          (pkgs.writeTextDir ".millennium/Dist/index.js" ''
            const pluginName = ${builtins.toJSON quickCssWatcher};
            (window.PLUGIN_LIST ||= {})[pluginName] ||= {};
            (async () => {
              window.PLUGIN_LIST[pluginName].__millennium_internal_plugin_name_do_not_use_or_change__ = pluginName;
              await window.MILLENNIUM_API.Millennium.callServerMethod("core", "Core_WatchQuickCss");
              MILLENNIUM_BACKEND_IPC.postMessage(1, { pluginName });
            })();
          '')
        ];
      };
    };

  settings = pkgs.writeText "millennium-settings.json" (
    builtins.toJSON {
      general.checkForPluginAndThemeUpdates = false;
      themes.activeTheme = theme;
      plugins.enabledPlugins = lib.attrNames plugins;
    }
  );

  fonts = lib.concatMapStringsSep ", " builtins.toJSON config.fonts.fontconfig.defaultFonts.sansSerif;

  quickCss = pkgs.writers.writePython3Bin "millennium-quick-css" { flakeIgnore = [ "E501" ]; } ''
    import json
    import os
    import sys

    colors = json.load(sys.stdin)


    def channels(value):
        value = value.lstrip("#")
        return [int(value[index:index + 2], 16) for index in (0, 2, 4)]


    def mix(start, end, percent):
        return [(a * (100 - percent) + b * percent) // 100 for a, b in zip(channels(start), channels(end))]


    c = colors
    variables = {
        "accent-1": channels(c["accent"]),
        "accent-2": channels(c["accentHover"]),
        "background": channels(c["background"]),
        "color-1": mix(c["background"], c["surface"], 33),
        "color-3": mix(c["background"], c["surface"], 66),
        "color-4": channels(c["surface"]),
        "color-2": mix(c["surface"], c["surfaceHover"], 50),
        "color-6": channels(c["surfaceHover"]),
        "color-5": mix(c["surfaceHover"], c["border"], 50),
    }
    for hue in ("red", "green", "blue", "yellow"):
        variables[hue] = channels(c[hue])
        variables[f"{hue}-hover"] = mix(c[hue], c["text"], 20)

    lines = "".join(f"  --st-{name}: {', '.join(map(str, rgb))};\n" for name, rgb in variables.items())
    css = (
        ":root * {\n"
        "  font-family: ${lib.escape [ "\\" "\"" ] fonts}, sans-serif !important;\n"
        "}\n"
        f":root:root {{\n{lines}}}\n"
    )

    path = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "millennium", "quick.css")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(css)
  '';

  applySettings = pkgs.writeShellApplication {
    name = "millennium-apply-settings";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      dir="''${XDG_CONFIG_HOME:-$HOME/.config}/millennium"
      config="$dir/config.json"
      layers=(${settings})

      mkdir -p "$dir"
      if [ -s "$config" ]; then
        layers=("$config" "''${layers[@]}")
      fi

      merged="$(mktemp "$config.XXXXXX")"
      trap 'rm -f "$merged"' EXIT
      jq --slurp 'reduce .[] as $layer ({}; . * $layer)' "''${layers[@]}" > "$merged"
      mv "$merged" "$config"
    '';
  };
in
{
  nixpkgs.overlays = [ inputs.millennium.overlays.default ];

  programs.steam = {
    enable = true;
    package = pkgs.millennium-steam.override {
      extraProfile = ''
        ${lib.getExe applySettings} || true
      '';
    };
    extraCompatPackages = [ inputs.chaotic.unrestrictedPackages.x86_64-linux.proton-cachyos ];
  };

  home-manager.users.keewai = {
    imports = [ (impastoPaletteHook "steam" "millennium/quick.css" quickCss) ];

    home.file.".local/share/Steam/millennium/themes/${theme}" = {
      source = inputs.millennium-theme-space;
      recursive = true;
    };

    xdg.dataFile = lib.mapAttrs' (name: source: {
      name = "millennium/plugins/${name}";
      value = {
        inherit source;
        recursive = true;
      };
    }) plugins;
  };
}
