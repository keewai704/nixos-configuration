{
  inputs,
  pkgs,
  ...
}:
let
  quickshell = pkgs.quickshell.overrideAttrs (old: {
    buildInputs = old.buildInputs ++ [ pkgs.qt6.qtmultimedia ];
  });

  shell = pkgs.runCommand "impasto-quickshell" { } ''
    cp -r ${inputs.impasto}/home/.config/quickshell $out
    chmod -R u+w $out
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

  settings = builtins.toJSON {
    superTapLauncher = true;
    themeTargets = [ ];
  };
in
{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  fonts.packages = [
    pkgs.inter
    pkgs.noto-fonts-color-emoji
  ];

  home-manager.users.keewai = {
    xdg.configFile = {
      quickshell.source = shell;
      hypr.source = hypr;
    };

    systemd.user.services.noctalia.Unit.ConditionEnvironment = "!XDG_CURRENT_DESKTOP=Hyprland";

    home.activation.impastoData = inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      data="''${XDG_DATA_HOME:-$HOME/.local/share}"
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"
      run mkdir -p "$data/wallpapers" "$state"
      run cp -rn --no-preserve=mode ${inputs.impasto}/home/.local/share/. "$data/"
      run install -m644 ${../wallpaper.png} "$data/wallpapers/noctalia.png"
      if [ ! -e "$state/settings.json" ]; then
        echo '${settings}' | run tee "$state/settings.json" > /dev/null
      fi
      if [ ! -e "$state/state.json" ]; then
        echo "{\"currentWallpaper\": \"$data/wallpapers/noctalia.png\"}" | run tee "$state/state.json" > /dev/null
      fi
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
