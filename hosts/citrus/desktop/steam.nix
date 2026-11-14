{
  config,
  impastoPalette,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  theme = "SpaceTheme";

  themeSource = pkgs.runCommand "millennium-${theme}" { } ''
    cp -r ${inputs.millennium-theme-space} $out
    chmod -R u+w $out
    cp ${rootColors} $out/src/css/root.css
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
      plugins.enabledPlugins = lib.attrNames plugins;
    }
  );

  channels =
    hex:
    map (start: lib.fromHexString (builtins.substring start 2 hex)) [
      1
      3
      5
    ];

  mix =
    from: to: percent:
    lib.zipListsWith (a: b: (a * (100 - percent) + b * percent) / 100) (channels from) (channels to);

  rootColors =
    with impastoPalette;
    pkgs.writeText "spacetheme-root.css" ''
      :root {
      ${
        lib.concatStrings (
          lib.mapAttrsToList (name: rgb: "    --st-${name}: ${lib.concatMapStringsSep ", " toString rgb};\n")
            {
              accent-1 = channels accent;
              accent-2 = channels accentHover;
              background = channels background;
              color-1 = mix background surface 33;
              color-3 = mix background surface 66;
              color-4 = channels surface;
              color-2 = mix surface surfaceHover 50;
              color-6 = channels surfaceHover;
              color-5 = mix surfaceHover border 50;
              red = channels red;
              red-hover = mix red text 20;
              green = channels green;
              green-hover = mix green text 20;
              blue = channels blue;
              blue-hover = mix blue text 20;
              yellow = channels yellow;
              yellow-hover = mix yellow text 20;
            }
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
