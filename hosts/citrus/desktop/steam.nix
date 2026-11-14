{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  theme = "Material-Theme";

  themeColors = "css/main/colors/matugen.css";

  themeSource = pkgs.runCommand "millennium-${theme}" { } ''
    cp -r ${inputs.millennium-theme-material} $out
    chmod -R u+w $out
    cp ${themeColorsCss} $out/${themeColors}
  '';

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
      themes.conditions.${theme} = {
        Color = "Matugen";
        Font = "Default";
      };
      plugins.enabledPlugins = lib.attrNames plugins;
    }
  );

  rgb =
    hex:
    "rgb(${
      lib.concatMapStringsSep ", " (start: toString (lib.fromHexString (builtins.substring start 2 hex)))
        [
          0
          2
          4
        ]
    })";

  themeColorsCss = pkgs.writeText "millennium-stylix.css" ''
    :root {
        --theme-color: "Matugen";
        --hue-rotate: 220deg;
    ${
      lib.concatStrings (
        lib.mapAttrsToList (name: hex: "    --md-sys-color-${name}: ${rgb hex};\n") (
          import ./material-colors.nix config.lib.stylix.colors
        )
      )
    }}
  '';

  quickCss = pkgs.writeText "millennium-quick.css" ''
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
    home.file.".local/share/Steam/millennium/themes/${theme}" = {
      source = themeSource;
      recursive = true;
    };

    xdg.dataFile = lib.mapAttrs' (name: source: {
      name = "millennium/plugins/${name}";
      value = {
        inherit source;
        recursive = true;
      };
    }) plugins;

    xdg.configFile."millennium/quick.css".source = quickCss;
  };
}
