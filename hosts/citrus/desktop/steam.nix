{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  theme = "SpaceTheme";

  plugins = lib.mapAttrs' (_: source: {
    inherit ((lib.importJSON "${source}/plugin.json")) name;
    value = source;
  }) (lib.filterAttrs (name: _: lib.hasPrefix "millennium-plugin-" name) inputs);

  settings = pkgs.writeText "millennium-settings.json" (
    builtins.toJSON {
      general.checkForPluginAndThemeUpdates = false;
      themes.activeTheme = theme;
      plugins.enabledPlugins = lib.attrNames plugins;
    }
  );

  color = token: "{{colors.${token}.dark.rgb_csv}}";

  noctaliaColors = pkgs.writeText "millennium-noctalia.json" (
    builtins.toJSON {
      themes.themeColors.${theme} = {
        "--st-accent-1" = color "primary";
        "--st-accent-2" = "{{colors.primary.dark.rgb_csv | lighten 8}}";
        "--st-background" = color "surface";
        "--st-color-1" = color "surface_container_low";
        "--st-color-2" = color "surface_container_highest";
        "--st-color-3" = color "surface_container";
        "--st-color-4" = color "surface_container_high";
        "--st-color-5" = color "surface_bright";
        "--st-color-6" = color "surface_bright";
        "--st-red" = color "error";
        "--st-red-hover" = "{{colors.error.dark.rgb_csv | lighten 8}}";
      };
    }
  );

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
      if [ -s "$dir/noctalia.json" ]; then
        layers+=("$dir/noctalia.json")
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
      input_path = "${noctaliaColors}";
      output_path = "$XDG_CONFIG_HOME/millennium/noctalia.json";
    };
  };
}
