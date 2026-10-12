{
  config,
  lib,
  pkgs,
  ...
}:
let
  state = "${config.xdg.stateHome}/quickshell";
  fonts = config.stylix.fonts;
  base = config.lib.stylix.colors;
  slots = {
    base00 = "background";
    base01 = "surface";
    base02 = "surfaceHover";
    base03 = "textMuted";
    base04 = "textMuted";
    base05 = "text";
    base06 = "text";
    base07 = "text";
    base08 = "red";
    base09 = "yellow";
    base0A = "yellow";
    base0B = "green";
    base0C = "accent";
    base0D = "accent";
    base0E = "accentHover";
    base0F = "red";
  };
  colors =
    lib.mapAttrs (_: name: "@impasto-${name}@") slots
    // lib.mapAttrs' (slot: name: lib.nameValuePair "${slot}-rgb" "@impasto-${name}-rgb@") slots;
  themeFile = name: config.lib.file.mkOutOfStoreSymlink "${state}/themes/${name}";
  fcitx = config.i18n.inputMethod.fcitx5.themes.stylix;
  fcitxTheme =
    lib.mapAttrsRecursive
      (
        _: value:
        if builtins.isBool value then
          (if value then "True" else "False")
        else if builtins.isString value then
          lib.replaceStrings (map (slot: "#${base.${slot}}") (builtins.attrNames slots)) (map (
            slot: "#${colors.${slot}}"
          ) (builtins.attrNames slots)) value
        else
          value
      )
      (
        lib.recursiveUpdate fcitx.theme {
          Metadata.Name = "Impasto";
          InputPanel = {
            HighlightColor = "#@impasto-accentText@";
            HighlightCandidateColor = "#@impasto-accentText@";
            HighlightBackgroundColor = "#@impasto-accent@";
          };
          "InputPanel/Highlight".Color = "#@impasto-accent@";
          Menu.HighlightCandidateColor = "#@impasto-accentText@";
          "Menu/Highlight".Color = "#@impasto-accent@";
        }
      );
  fcitxImages = pkgs.runCommand "impasto-fcitx-templates" { } ''
    mkdir -p "$out"
    substitute ${fcitx.panelImage} "$out/panel.svg" \
      --replace-fail 'fill:#${base.base00}' 'fill:#@impasto-background@' \
      --replace-fail 'stroke:#${base.base01}' 'stroke:#@impasto-border@'
    substitute ${fcitx.highlightImage} "$out/highlight.svg" \
      --replace-fail 'fill:#${base.base02}' 'fill:#@impasto-accent@'
  '';
  fallback = pkgs.writeText "impasto-fallback-palette.json" (
    builtins.toJSON {
      background = "#${base.base00}";
      surface = "#${base.base01}";
      surfaceHover = "#${base.base02}";
      border = "#${base.base02}";
      text = "#${base.base05}";
      textMuted = "#${base.base04}";
      accent = "#${base.base0D}";
      accentHover = "#${base.base0E}";
      accentText = "#${base.base00}";
      red = "#${base.base08}";
      yellow = "#${base.base0A}";
      green = "#${base.base0B}";
    }
  );
in
{
  config = lib.mkIf config.programs.island.enable {
    xdg.configFile = {
      "quickshell/theme-templates/legcord.css".text = import ./legcord-system24.nix {
        inherit colors fonts;
      };
      "quickshell/theme-templates/steam.css".text = import ./steam-css.nix {
        inherit colors fonts;
      };
      "quickshell/theme-templates/fcitx5/theme.conf".source =
        (pkgs.formats.ini { }).generate "impasto-fcitx-template.conf"
          fcitxTheme;
      "quickshell/theme-templates/fcitx5/panel.svg".source = "${fcitxImages}/panel.svg";
      "quickshell/theme-templates/fcitx5/highlight.svg".source = "${fcitxImages}/highlight.svg";
      "legcord/quickCss.css".source = themeFile "legcord.css";
      "millennium/quick.css".source = themeFile "steam.css";
    };

    i18n.inputMethod.fcitx5.settings.addons.classicui.globalSection.Theme = lib.mkForce "impasto";
    xdg.dataFile =
      lib.genAttrs
        (map (name: "fcitx5/themes/impasto/${name}") [
          "theme.conf"
          "panel.svg"
          "highlight.svg"
        ])
        (path: {
          source = themeFile "fcitx5/${builtins.baseNameOf path}";
        });

    home.activation.islandAppThemes = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${config.programs.island.package}/share/quickshell/island/scripts/theme_manager.py \
        render-themes ${fallback}
    '';
  };
}
