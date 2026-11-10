{
  config,
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
      themes.conditions.${theme}.Font = "Arial";
      plugins.enabledPlugins = lib.attrNames plugins;
    }
  );

  color = token: "{{colors.${token}.dark.rgb_csv}}";

  quickCss = pkgs.writeText "millennium-quick.css" ''
    :root {
    ${
      lib.concatStrings (
        lib.mapAttrsToList (name: value: "  --st-${name}: ${value} !important;\n") {
          accent-1 = color "primary";
          accent-2 = "{{colors.primary.dark.rgb_csv | lighten 8}}";
          background = color "surface";
          color-1 = color "surface_container_low";
          color-2 = color "surface_container_highest";
          color-3 = color "surface_container";
          color-4 = color "surface_container_high";
          color-5 = color "surface_bright";
          color-6 = color "surface_bright";
          red = color "error";
          red-hover = "{{colors.error.dark.rgb_csv | lighten 8}}";
        }
      )
    }}

    :root * {
      font-family: ${
        lib.concatMapStringsSep ", " builtins.toJSON config.fonts.fontconfig.defaultFonts.sansSerif
      }, sans-serif !important;
    }
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
    home.file.".local/share/Steam/millennium/themes/${theme}".source =
      inputs.millennium-theme-spacetheme;

    xdg.dataFile = lib.mapAttrs' (name: source: {
      name = "millennium/plugins/${name}";
      value = {
        inherit source;
        recursive = true;
      };
    }) plugins;

    programs.noctalia.settings.theme.templates.user.millennium = {
      input_path = "${quickCss}";
      output_path = "$XDG_CONFIG_HOME/millennium/quick.css";
    };
  };
}
