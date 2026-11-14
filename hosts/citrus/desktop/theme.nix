{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  fcitx5 = config.home-manager.users.keewai.i18n.inputMethod.fcitx5;

  fcitx5Value =
    value:
    if lib.isAttrs value then
      lib.mapAttrs (_: fcitx5Value) value
    else if lib.isBool value then
      if value then "True" else "False"
    else
      value;
in
{
  imports = [ inputs.stylix.nixosModules.stylix ];

  stylix = {
    enable = true;
    image = ./wallpaper.png;
    polarity = "dark";
    targets.limine.image.enable = false;

    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 24;
    };

    icons = {
      enable = true;
      package = pkgs.papirus-icon-theme;
      dark = "Papirus-Dark";
      light = "Papirus-Light";
    };

    fonts = {
      sansSerif = {
        package = pkgs.noto-fonts-cjk-sans;
        name = "Noto Sans CJK JP";
      };
      serif = {
        package = pkgs.noto-fonts-cjk-serif;
        name = "Noto Serif CJK JP";
      };
      monospace = {
        package = pkgs.udev-gothic;
        name = "UDEV Gothic";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
    };
  };

  i18n.inputMethod.fcitx5.settings.addons.classicui.globalSection =
    fcitx5Value fcitx5.settings.addons.classicui.globalSection;

  home-manager.users.keewai = {
    stylix.targets.zen-browser.profileNames = [ "default" ];

    xdg.dataFile = with fcitx5.themes.stylix; {
      "fcitx5/themes/stylix/theme.conf".source = (pkgs.formats.ini { }).generate "fcitx5-stylix-theme" (
        fcitx5Value theme
      );
      "fcitx5/themes/stylix/panel.svg".source = panelImage;
      "fcitx5/themes/stylix/highlight.svg".source = highlightImage;
    };

    gtk = {
      gtk3.extraConfig.gtk-im-module = "fcitx";
      gtk4.extraConfig.gtk-im-module = "fcitx";
    };

    home.file.".pi/agent/themes/stylix.json".text = builtins.toJSON {
      "$schema" =
        "https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json";
      name = "stylix";
      colors = with config.lib.stylix.colors.withHashtag; {
        accent = base0D;
        border = base03;
        borderAccent = base0D;
        borderMuted = base02;
        success = base0B;
        error = base08;
        warning = base0A;
        muted = base04;
        dim = base03;
        text = "";
        thinkingText = base04;
        selectedBg = base02;
        userMessageBg = base01;
        userMessageText = base05;
        customMessageBg = base01;
        customMessageText = base05;
        customMessageLabel = base0D;
        toolPendingBg = base00;
        toolSuccessBg = base01;
        toolErrorBg = base02;
        toolTitle = base0D;
        toolOutput = "";
        mdHeading = base0D;
        mdLink = base0C;
        mdLinkUrl = base04;
        mdCode = base0B;
        mdCodeBlock = "";
        mdCodeBlockBorder = base02;
        mdQuote = base04;
        mdQuoteBorder = base02;
        mdHr = base02;
        mdListBullet = base0C;
        toolDiffAdded = base0B;
        toolDiffRemoved = base08;
        toolDiffContext = base04;
        syntaxComment = base03;
        syntaxKeyword = base0E;
        syntaxFunction = base0D;
        syntaxVariable = base05;
        syntaxString = base0B;
        syntaxNumber = base09;
        syntaxType = base0A;
        syntaxOperator = base0C;
        syntaxPunctuation = base04;
        thinkingOff = base02;
        thinkingMinimal = base03;
        thinkingLow = base0D;
        thinkingMedium = base0C;
        thinkingHigh = base09;
        thinkingXhigh = base08;
        bashMode = base0B;
      };
    };

    home.activation.piTheme = inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      settings="$HOME/.pi/agent/settings.json"
      run mkdir -p "$(dirname "$settings")"
      [ -s "$settings" ] || echo '{}' > "$settings"
      merged="$(mktemp "$settings.XXXXXX")"
      ${lib.getExe pkgs.jq} '.theme = "stylix"' "$settings" > "$merged"
      run mv "$merged" "$settings"
    '';
  };
}
