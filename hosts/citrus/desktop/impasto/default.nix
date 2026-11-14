{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  wallpaper = config.stylix.image;

  quickshell = pkgs.quickshell.overrideAttrs (old: {
    buildInputs = old.buildInputs ++ [ pkgs.qt6.qtmultimedia ];
  });

  shell = pkgs.runCommand "impasto-quickshell" { } ''
    cp -r ${inputs.impasto}/home/.config/quickshell $out
    chmod -R u+w $out
    patch -p0 -d $out < ${./adaptive-variants.patch}
    substituteInPlace $out/scripts/emoji.py \
      --replace-fail /usr/share/unicode/emoji ${pkgs.unicode-emoji}/share/unicode/emoji \
      --replace-fail /usr/share/unicode/cldr ${pkgs.cldr-annotations}/share/unicode/cldr \
      --replace-fail /usr/share/iso-codes ${pkgs.isocodes}/share/iso-codes
    substituteInPlace $out/scripts/compositor.py \
      --replace-fail /usr/share/X11/xkb ${pkgs.xkeyboard_config}/share/X11/xkb
  '';

  hypr = pkgs.runCommand "impasto-hypr" { } ''
    cp -r ${inputs.impasto}/home/.config/hypr $out
    chmod -R u+w $out
    install -Dm644 -t $out/custom ${./hypr}/*.lua
    substituteInPlace $out/modules/programs.lua \
      --replace-fail '"nautilus --new-window"' '"thunar"'
  '';

  colors =
    pkgs.runCommand "impasto-colors.json"
      {
        nativeBuildInputs = [
          pkgs.imagemagick
          pkgs.python3
        ];
      }
      ''
        HOME=$TMPDIR python3 ${./scheme.py} ${shell}/scripts ${wallpaper} > $out
      '';

  greeter = pkgs.runCommand "impasto-sddm-theme" { } ''
    mkdir -p $out/share/sddm/themes
    cp -r ${inputs.impasto}/system/usr/share/sddm/themes/impasto $out/share/sddm/themes/impasto
    chmod -R u+w $out
    install -m644 ${wallpaper} $out/share/sddm/themes/impasto/background.jpg
  '';

  initialSettings = builtins.toJSON { superTapLauncher = true; };

  settings = builtins.toJSON {
    dockEnabled = false;
    themeTargets = [ ];
  };

  jq = lib.getExe pkgs.jq;
in
{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = true;
      theme = "impasto";
    };
    autoLogin = {
      enable = true;
      user = "keewai";
    };
    defaultSession = "hyprland-uwsm";
  };

  hardware.bluetooth.enable = true;
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;

  environment.systemPackages = [ greeter ];

  fonts.packages = [ pkgs.inter ];

  _module.args.impastoPalette = (lib.importJSON colors).palette;

  stylix.base16Scheme = (lib.importJSON colors).base16;

  home-manager.users.keewai = {
    xdg.configFile = {
      quickshell.source = shell;
      hypr.source = hypr;
    };

    programs.cava.enable = true;

    home.activation.impastoData = inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      data="''${XDG_DATA_HOME:-$HOME/.local/share}"
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"
      current="$data/wallpapers/citrus.png"
      run mkdir -p "$data/wallpapers" "$state"
      run cp -rn --no-preserve=mode ${inputs.impasto}/home/.local/share/. "$data/"
      run install -m644 ${wallpaper} "$current"
      run ln -sfn "$current" "$state/current-wallpaper"

      [ -s "$state/settings.json" ] || echo '${initialSettings}' > "$state/settings.json"
      [ -s "$state/state.json" ] || echo '{}' > "$state/state.json"

      merged="$(mktemp "$state/settings.json.XXXXXX")"
      ${jq} '. * ${settings}' "$state/settings.json" > "$merged"
      run mv "$merged" "$state/settings.json"

      merged="$(mktemp "$state/state.json.XXXXXX")"
      ${jq} --arg wallpaper "$current" '.activeTheme = "adaptive" | .currentWallpaper = $wallpaper' \
        "$state/state.json" > "$merged"
      run mv "$merged" "$state/state.json"
    '';

    home.packages = [
      pkgs.awww
      pkgs.brightnessctl
      pkgs.ffmpeg
      pkgs.grim
      pkgs.gtk3
      pkgs.hyprpicker
      pkgs.hyprshutdown
      pkgs.hyprsunset
      pkgs.imagemagick
      pkgs.libnotify
      pkgs.playerctl
      pkgs.pulseaudio
      quickshell
      pkgs.satty
      pkgs.songrec
      pkgs.tesseract
      pkgs.wf-recorder
      pkgs.wl-screenrec
      pkgs.xdg-utils
    ];
  };
}
