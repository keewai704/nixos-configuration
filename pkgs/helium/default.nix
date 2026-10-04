{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  patchelf,
  bintools,
  addDriverRunpath,
  adwaita-icon-theme,
  gsettings-desktop-schemas,
  xdg-utils,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  bzip2,
  cairo,
  coreutils,
  cups,
  curl,
  dbus,
  expat,
  flac,
  fontconfig,
  freetype,
  gcc-unwrapped,
  gdk-pixbuf,
  glib,
  gtk3,
  gtk4,
  harfbuzz,
  icu,
  libcap,
  libdrm,
  libexif,
  libgbm,
  libglvnd,
  libkrb5,
  libopus,
  libpng,
  libpulseaudio,
  libva,
  libx11,
  libxcb,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxkbcommon,
  libxrandr,
  libxrender,
  libxscrnsaver,
  libxshmfence,
  libxtst,
  nspr,
  nss,
  pango,
  pciutils,
  pipewire,
  snappy,
  speechd-minimal,
  systemd,
  util-linux,
  vulkan-loader,
  wayland,
  commandLineArgs ? "--lang=ja --accept-lang=ja-JP,ja,en-US,en",
}:

let
  deps = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    bzip2
    cairo
    coreutils
    cups
    curl
    dbus
    expat
    flac
    fontconfig
    freetype
    gcc-unwrapped.lib
    gdk-pixbuf
    glib
    gtk3
    gtk4
    harfbuzz
    icu
    libcap
    libdrm
    libexif
    libgbm
    libglvnd
    libkrb5
    (libopus.override { withCustomModes = true; })
    libpng
    libpulseaudio
    libva
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libxrender
    libxscrnsaver
    libxshmfence
    libxtst
    nspr
    nss
    pango
    pciutils
    pipewire
    snappy
    speechd-minimal
    systemd
    util-linux
    vulkan-loader
    wayland
  ];
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "helium";
  version = "0.18.2.1";

  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${finalAttrs.version}/helium-${finalAttrs.version}-x86_64_linux.tar.xz";
    hash = "sha256-RJPXVrmK++P9fUXA7CFcI/WgVR+ucVWG/mzjsimLFVw=";
  };

  nativeBuildInputs = [
    makeWrapper
    patchelf
  ];

  buildInputs = [
    adwaita-icon-theme
    glib
    gtk3
    gtk4
    gsettings-desktop-schemas
  ];

  strictDeps = false;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;

  rpath = lib.makeLibraryPath deps + ":" + lib.makeSearchPathOutput "lib" "lib64" deps;

  installPhase = ''
    runHook preInstall

    app=$out/libexec/helium
    mkdir -p $app $out/bin $out/share/applications $out/share/icons/hicolor/256x256/apps
    cp -a . $app

    rm $app/libvulkan.so.1
    ln -s ${lib.getLib vulkan-loader}/lib/libvulkan.so.1 $app/libvulkan.so.1

    for elf in $app/helium $app/helium_crashpad_handler $app/chromedriver; do
      patchelf --set-interpreter ${bintools.dynamicLinker} --set-rpath "$rpath:$app" $elf
    done

    makeWrapper $app/helium $out/bin/helium \
      --prefix LD_LIBRARY_PATH : "$rpath:$app" \
      --suffix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH:${addDriverRunpath.driverLink}/share" \
      --set CHROME_WRAPPER helium \
      --set CHROME_VERSION_EXTRA nixos \
      --set LANG ja_JP.UTF-8 \
      --set LANGUAGE ja_JP:ja \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
      --add-flags ${lib.escapeShellArg commandLineArgs}

    mv $app/helium.desktop $out/share/applications/helium.desktop
    mv $app/product_logo_256.png $out/share/icons/hicolor/256x256/apps/helium.png
    substituteInPlace $out/share/applications/helium.desktop \
      --replace-fail "Exec=helium" "Exec=$out/bin/helium"

    runHook postInstall
  '';

  meta = {
    description = "Private, fast, and honest web browser based on Chromium";
    homepage = "https://helium.computer";
    license = lib.licenses.gpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "helium";
  };
})
