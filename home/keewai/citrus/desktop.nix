{
  osConfig,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  chatgptDesktop = pkgs.callPackage ../../../pkgs/chatgpt-desktop { };
  thunar = pkgs.thunar.override {
    thunarPlugins = [
      pkgs.thunar-archive-plugin
      pkgs.thunar-volman
    ];
  };

in
{
  home.packages = [
    (pkgs.callPackage ../../../pkgs/apple-music-client {
      src = inputs.apple-music-client;
      authService = inputs.apple-music-client.packages.${pkgs.stdenv.hostPlatform.system}.auth-service;
    })
    inputs.apple-music-client.packages.${pkgs.stdenv.hostPlatform.system}.auth-service
    chatgptDesktop
    pkgs.brightnessctl
    pkgs.ddcutil
    pkgs.grimblast
    pkgs.networkmanagerapplet
    pkgs.pavucontrol
    pkgs.yt-dlp
    pkgs.gws
    pkgs.xarchiver
    thunar
    pkgs.xfconf
    pkgs.noto-fonts
  ];

  systemd.user.packages = [ pkgs.xfconf ];

  imports = [ inputs.nixcord.homeModules.nixcord ];

  # Steam reads user fontconfig; keep semibold Japanese text in the sans family.
  fonts.fontconfig = {
    enable = true;
    defaultFonts.sansSerif = osConfig.fonts.fontconfig.defaultFonts.sansSerif ++ [ "Noto Sans CJK JP" ];
  };

  xdg = {
    mimeApps.defaultApplications."inode/directory" = [ "thunar.desktop" ];
    userDirs = {
      enable = true;
      createDirectories = true;
    };

    configFile = {
      # The plugin wrapper fixes lib/systemd/user; share still starts raw Thunar.
      "systemd/user/thunar.service".source = "${thunar}/lib/systemd/user/thunar.service";
      "alac-room/theme.json".text = builtins.toJSON {
        colors = lib.getAttrs [
          "base00"
          "base01"
          "base02"
          "base03"
          "base04"
          "base05"
          "base06"
          "base07"
          "base08"
          "base09"
          "base0A"
          "base0B"
          "base0C"
          "base0D"
          "base0E"
          "base0F"
        ] osConfig.lib.stylix.colors;
        fontFamily = osConfig.stylix.fonts.sansSerif.name;
        fontSize = osConfig.stylix.fonts.sizes.applications * 4.0 / 3.0;
        polarity = osConfig.stylix.polarity;
      };
      "user-dirs.dirs".force = true;
      # Link only managed files so Fcitx5 can still save its other settings.
      fcitx5.recursive = true;

      "legcord/quickCss.css".text = import ./system24.nix {
        colors = osConfig.lib.stylix.colors;
        fonts = osConfig.stylix.fonts;
      };

      # SpaceTheme uses comma-separated RGB channels; keep its layout and plugins.
      "millennium/quick.css".source = osConfig.lib.stylix.colors {
        template = pkgs.writeText "millennium.css.mustache" ''
          /* Managed by Stylix for SpaceTheme for Steam. */
          :root {
            --st-accent-1: {{base0D-rgb-r}}, {{base0D-rgb-g}}, {{base0D-rgb-b}} !important;
            --st-accent-2: {{base0E-rgb-r}}, {{base0E-rgb-g}}, {{base0E-rgb-b}} !important;
            --st-background: {{base00-rgb-r}}, {{base00-rgb-g}}, {{base00-rgb-b}} !important;
            --st-color-1: {{base00-rgb-r}}, {{base00-rgb-g}}, {{base00-rgb-b}} !important;
            --st-color-2: {{base01-rgb-r}}, {{base01-rgb-g}}, {{base01-rgb-b}} !important;
            --st-color-3: {{base00-rgb-r}}, {{base00-rgb-g}}, {{base00-rgb-b}} !important;
            --st-color-4: {{base01-rgb-r}}, {{base01-rgb-g}}, {{base01-rgb-b}} !important;
            --st-color-5: {{base02-rgb-r}}, {{base02-rgb-g}}, {{base02-rgb-b}} !important;
            --st-color-6: {{base03-rgb-r}}, {{base03-rgb-g}}, {{base03-rgb-b}} !important;
            --st-blue: {{base0D-rgb-r}}, {{base0D-rgb-g}}, {{base0D-rgb-b}} !important;
            --st-blue-hover: var(--st-blue) !important;
            --st-green: {{base0B-rgb-r}}, {{base0B-rgb-g}}, {{base0B-rgb-b}} !important;
            --st-green-hover: var(--st-green) !important;
            --st-red: {{base08-rgb-r}}, {{base08-rgb-g}}, {{base08-rgb-b}} !important;
            --st-red-hover: var(--st-red) !important;
            --st-yellow: {{base0A-rgb-r}}, {{base0A-rgb-g}}, {{base0A-rgb-b}} !important;
            --st-yellow-hover: var(--st-yellow) !important;
          }
          :root * {
            font-family: "${osConfig.stylix.fonts.sansSerif.name}", sans-serif !important;
          }

          /* Give settings rows one card; Steam places controls outside FieldLabelRow. */
          :root body .DialogBody > .Panel,
          :root body .DialogBody .DialogControlsSection > .Panel {
            padding: 12px !important;
            margin-bottom: 12px !important;
            border-radius: var(--st-border-radius);
            background-color: rgb(var(--st-color-2));
          }
          body .DialogBody .eKmEXJCm_lgme24Fp_HWt ._2tALpM7z8naXJ35Pp5fNAG > :is(._2VcTlXFC64Jtg9gvtT6cmY, ._1W1to_azoBRG95oNAFpf9Q) {
            padding: 0 !important;
            background: none !important;
          }
          body .DialogBody .eKmEXJCm_lgme24Fp_HWt ._1W1to_azoBRG95oNAFpf9Q {
            margin-top: 6px;
          }
          /* Section headings also precede help text and inputs without a Panel wrapper. */
          body .DialogBody :is(.DialogSubHeader, .SettingsDialogSubHeader) {
            padding: 12px 0 6px;
            background: none;
          }
          /* Disabled switch tracks and thumbs must remain visible on the shared palette. */
          :root ._9Ql-oVe_j8E-vsDdyVdWo.aIeh3X5T2M074RLW1qn6_ ._2bl0iQ9xigbq4Zd1NI6NZl {
            background-color: rgb(var(--st-color-5)) !important;
          }
          :root ._9Ql-oVe_j8E-vsDdyVdWo.aIeh3X5T2M074RLW1qn6_ ._1PQppcgkuXQAiFPar9AGi- {
            background-color: rgb(var(--st-color-6));
          }
        '';
        extension = ".css";
      };
    };
  };

  programs.kitty = {
    enable = true;
    font = {
      package = lib.mkForce pkgs.hackgen-nf-font;
      name = lib.mkForce "HackGen Console NF";
      size = lib.mkForce 12;
    };
  };

  programs.nixcord = {
    enable = true;
    discord.enable = false;
    legcord = {
      enable = true;
      equicord.enable = true;
      settings = {
        quickCss = true;
        windowStyle = "default";
      };
    };
  };

  gtk = {
    colorScheme = "dark";
    gtk2.enable = false;
  };

  stylix.targets = {
    font-packages.enable = true;
    fcitx5.enable = true;
    firefox.enable = false;
    gtk = {
      enable = true;
      flatpakSupport.enable = false;
    };
    hyprland.enable = false;
    kitty.enable = true;
    # System24 maps its own palette to Discord's component colors.
    nixcord.enable = false;
    qt = {
      enable = true;
      standardDialogs = "xdgdesktopportal";
    };
  };

}
