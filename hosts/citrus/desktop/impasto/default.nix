{
  config,
  inputs,
  lib,
  pkgs,
  updateJson,
  ...
}:
let
  wallpaper = ../wallpaper.png;

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
    substituteInPlace $out/services/BrightnessService.qml \
      --replace-fail '"--noverify", "--skip-ddc-checks",' '"--noverify",'
  '';

  hypr = pkgs.runCommand "impasto-hypr" { } ''
    cp -r ${inputs.impasto}/home/.config/hypr $out
    chmod -R u+w $out
    install -Dm644 -t $out/custom ${./hypr}/*.lua
    echo 'hl.env("QS_ICON_THEME", "${config.home-manager.users.keewai.gtk.iconTheme.name}")' >> $out/custom/env.lua
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

  seedPalette = lib.importJSON colors;

  greeter = pkgs.runCommand "impasto-sddm-theme" { } ''
    mkdir -p $out/share/sddm/themes
    cp -r ${inputs.impasto}/system/usr/share/sddm/themes/impasto $out/share/sddm/themes/impasto
    chmod -R u+w $out
    install -m644 ${wallpaper} $out/share/sddm/themes/impasto/background.jpg
  '';

  initialSettings = builtins.toJSON { superTapLauncher = true; };

  settings = builtins.toJSON {
    barScreens = "primary";
    dockEnabled = false;
    pureBlack = true;
    terminalGround = "classic";
    workspaceMode = "screen";
  };

  barRight = builtins.toJSON [
    "claude"
    "opencode"
    "tray"
    "notifications"
    "network"
    "bluetooth"
    "volume"
    "battery"
  ];
in
{
  imports = [ ./bitwarden ];

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

  _module.args.impastoSeed = seedPalette;

  _module.args.impastoPaletteHook =
    name: target: script:
    let
      hook = lib.getExe script;
      seed = pkgs.writeText "impasto-palette.json" (builtins.toJSON seedPalette);
    in
    {
      xdg.configFile."impasto/palette-hooks/${name}".source = hook;
      home.activation."impastoPalette-${name}" =
        inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ]
          ''
            [ -e "''${XDG_CONFIG_HOME:-$HOME/.config}/${target}" ] || run ${hook} < ${seed}
          '';
    };

  home-manager.users.keewai = {
    xdg.configFile = {
      quickshell.source = shell;
      hypr.source = hypr;
    };

    programs.kitty = {
      settings = {
        allow_remote_control = "socket-only";
        listen_on = "unix:\${XDG_RUNTIME_DIR}/kitty.sock";
      };
      extraConfig = ''
        include ~/.local/state/quickshell/kitty-palette.conf
        include ~/.local/state/quickshell/kitty-font.conf
        include ~/.local/state/quickshell/kitty-ground.conf
      '';
    };

    programs.btop.settings.color_theme = "impasto";

    programs.cava = {
      enable = true;
      settings.color.theme = "impasto";
    };

    home.activation.impastoData = inputs.home-manager.lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      data="''${XDG_DATA_HOME:-$HOME/.local/share}"
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"
      current="$data/wallpapers/citrus.png"
      run mkdir -p "$data/wallpapers" "$state"
      run cp -rn --no-preserve=mode ${inputs.impasto}/home/.local/share/. "$data/"
      run install -m644 ${wallpaper} "$current"
      [ -e "$state/current-wallpaper" ] || run ln -sfn "$current" "$state/current-wallpaper"

      [ -s "$state/settings.json" ] || echo '${initialSettings}' > "$state/settings.json"
      [ -s "$state/state.json" ] || echo '{}' > "$state/state.json"

      run ${updateJson} "$state/settings.json" \
        '. * ${settings} | if .themeTargets == [] then del(.themeTargets) else . end | .barRight //= ${barRight}'
      run ${updateJson} "$state/state.json" --arg wallpaper "$current" \
        '.activeTheme //= "adaptive" | .currentWallpaper //= $wallpaper'
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
      pkgs.tesseract
      pkgs.wf-recorder
      pkgs.wl-screenrec
      pkgs.xdg-utils
    ];
  };
}
