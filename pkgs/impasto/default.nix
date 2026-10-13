{
  lib,
  stdenvNoCC,
  makeWrapper,
  impasto,
  quickshell,
  python3,
  awww,
  bluez,
  cava,
  cldr-annotations,
  dbus,
  fontconfig,
  grim,
  gtk3,
  hyprland,
  hyprpicker,
  hyprsunset,
  imagemagick,
  isocodes,
  libnotify,
  mpvpaper,
  networkmanager,
  papirus-icon-theme,
  playerctl,
  power-profiles-daemon,
  pulseaudio,
  satty,
  slurp,
  systemd,
  tesseract,
  unicode-emoji,
  wf-recorder,
  wireplumber,
  wl-clipboard,
  wl-screenrec,
  xdg-user-dirs,
  xdg-utils,
  xkeyboard_config,
}:
let
  runtime = [
    python3
    awww
    bluez
    cava
    dbus
    fontconfig
    grim
    gtk3
    hyprland
    hyprpicker
    hyprsunset
    imagemagick
    libnotify
    mpvpaper
    networkmanager
    playerctl
    power-profiles-daemon
    pulseaudio
    quickshell
    satty
    slurp
    systemd
    tesseract
    wf-recorder
    wireplumber
    wl-clipboard
    wl-screenrec
    xdg-user-dirs
    xdg-utils
  ];
in
stdenvNoCC.mkDerivation {
  pname = "impasto";
  version = "0-unstable-${lib.substring 0 7 impasto.rev}";
  src = impasto;
  patches = [ ./adaptive-colors.patch ];
  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ imagemagick ];
  buildInputs = [ python3 ];
  dontBuild = true;

  postPatch = ''
    shell=home/.config/quickshell
    substituteInPlace "$shell/components/TrayIcon.qml" \
      --replace-fail /usr/share/icons/Papirus-Dark ${papirus-icon-theme}/share/icons/Papirus-Dark
    {
      echo ".pragma library"
      echo "var names = {"
      for icon in ${papirus-icon-theme}/share/icons/Papirus-Dark/22x22/panel/*.svg; do
        name=''${icon##*/}
        echo "  \"''${name%.svg}\": true,"
      done
      echo "}"
    } > "$shell/components/panel-icons.js"
    substituteInPlace "$shell/scripts/emoji.py" \
      --replace-fail /usr/share/unicode/emoji ${unicode-emoji}/share/unicode/emoji \
      --replace-fail /usr/share/unicode/cldr ${cldr-annotations}/share/unicode/cldr \
      --replace-fail /usr/share/iso-codes ${isocodes}/share/iso-codes
    substituteInPlace "$shell/scripts/compositor.py" \
      --replace-fail /usr/share/X11/xkb/rules ${xkeyboard_config}/share/xkeyboard-config-2/rules
    substituteInPlace "$shell/services/ShortcutService.qml" \
      --replace-fail 'Island · Open the wallpaper effects' 'Shell · Open the wallpaper effects' \
      --replace-fail '        { name: "lock",           label: "Lock the screen",      description: "Session · Lock the screen" },' "" \
      --replace-fail '        { name: "packages",       label: "Packages",             description: "Shell · Open the packages" },' "" \
      --replace-fail '["Shell · Open the notes", "Shell · Open the task board"]' \
        '["Shell · Open the notes", "Shell · Open the task board", "Session · Lock the screen", "Shell · Open the packages"]'
    substituteInPlace "$shell/services/VersionService.qml" \
      --replace-fail '`''${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/impasto/version`' \
        '"'"$out"'/share/impasto/version"'
    substituteInPlace home/.local/bin/impasto \
      --replace-fail '["qs", "ipc", "call",' '["qs", "--path", "'"$out"'/share/quickshell/impasto", "ipc", "call",' \
      --replace-fail 'os.path.join(config, "quickshell", "scripts", "capture.py")' '"'"$out"'/share/quickshell/impasto/scripts/capture.py"' \
      --replace-fail 'os.path.join(state, "impasto", "version")' '"'"$out"'/share/impasto/version"'
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    export PYTHONDONTWRITEBYTECODE=1
    for script in home/.config/quickshell/scripts/*.py home/.local/bin/impasto; do
      python3 -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$script"
    done
    IMPASTO_APPLY_SETTINGS=${./apply-settings.py} python3 ${./test-apply-settings.py}
    python3 -m unittest discover -s tests
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    shell="$out/share/quickshell/impasto"
    mkdir -p "$shell" "$out/bin" "$out/share/impasto"
    cp -r home/.config/quickshell/. "$shell/"
    chmod +x "$shell"/scripts/*.py
    cp -r home/.local/share/wallpapers "$out/share/impasto/wallpapers"
    mkdir -p "$out/share/fonts/truetype"
    install -m644 home/.local/share/fonts/*.ttf "$out/share/fonts/truetype/"
    printf '%s\nmain\n' '${impasto.rev}' > "$out/share/impasto/version"
    install -Dm755 home/.local/bin/impasto "$out/bin/impasto"
    install -Dm755 ${./apply-settings.py} "$out/libexec/impasto-apply-settings"
    patchShebangs "$out"

    makeWrapper ${lib.getExe quickshell} "$out/bin/impasto-shell" \
      --add-flags "--path $shell" \
      --prefix PATH : ${lib.makeBinPath runtime} \
      --set-default QS_ICON_THEME Papirus-Dark \
      --set-default QSG_RENDER_LOOP threaded \
      --suffix XDG_DATA_DIRS : ${papirus-icon-theme}/share \
      --run 'if [ -z "''${TZDIR-}" ] && [ -d /etc/zoneinfo ]; then export TZDIR=/etc/zoneinfo; fi'
    makeWrapper ${lib.getExe quickshell} "$out/bin/impastoctl" \
      --add-flags "--path $shell ipc call"
    wrapProgram "$out/bin/impasto" --prefix PATH : ${lib.makeBinPath runtime}
    runHook postInstall
  '';

  meta = {
    description = "Impasto desktop shell and CLI for Hyprland";
    homepage = "https://github.com/keewai704/impasto";
    license = lib.licenses.gpl3Only;
    mainProgram = "impasto-shell";
    platforms = lib.platforms.linux;
  };
}
