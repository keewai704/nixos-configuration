{
  alsa-lib,
  at-spi2-core,
  autoPatchelfHook,
  bash,
  cairo,
  coreutils,
  cups,
  dbus,
  dpkg,
  expat,
  fetchurl,
  fontconfig,
  freetype,
  gdk-pixbuf,
  git,
  glib,
  graphite2,
  gtk3,
  lib,
  libdrm,
  libGL,
  libnotify,
  libsecret,
  libusb1,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  mesa,
  nspr,
  nss,
  openssl,
  pango,
  python3,
  stdenv,
  systemd,
  trash-cli,
  vulkan-loader,
  xdg-utils,
  xz,
}:

let
  version = "26.901.51231";
  runtimeLibraries = [
    alsa-lib
    at-spi2-core
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    graphite2
    gtk3
    libdrm
    libGL
    libnotify
    libsecret
    libusb1
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    mesa
    nspr
    nss
    openssl
    pango
    systemd
    vulkan-loader
    xz
  ];
in
stdenv.mkDerivation {
  pname = "chatgpt-desktop";
  inherit version;

  src = fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${version}_amd64.deb";
    hash = "sha256-YlgBiNh8PTqTadq3xztCqKMlGNTfii1brmRm3erFwF4=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
  ];

  buildInputs = runtimeLibraries;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --extract "$src" .
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;

  autoPatchelfIgnoreMissingDeps = [
    "libc.musl-x86_64.so.1"

    "libQt5Core.so.5"
    "libQt5Gui.so.5"
    "libQt5Widgets.so.5"
    "libQt6Core.so.6"
    "libQt6Gui.so.6"
    "libQt6Widgets.so.6"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/lib" "$out/share/applications" "$out/share/pixmaps"
    cp -r usr/lib/chatgpt "$out/lib/"
    appAsar="$out/lib/chatgpt/resources/app.asar"
    chmod u+rw "$appAsar"
    ${python3}/bin/python3 ${./patch-asar.py} "$appAsar"

    substitute ${./launch-chatgpt.sh} "$out/lib/chatgpt/launch-chatgpt" \
      --replace-fail '#!/usr/bin/env bash' '#!${lib.getExe bash}' \
      --subst-var-by runtimeLibraries '${lib.makeLibraryPath runtimeLibraries}' \
      --subst-var-by runtimePath '${
        lib.makeBinPath [
          coreutils
          git
          glib
          trash-cli
          xdg-utils
        ]
      }' \
      --subst-var out \
      --subst-var version
    chmod 0755 "$out/lib/chatgpt/launch-chatgpt"
    ln -s ../lib/chatgpt/launch-chatgpt "$out/bin/chatgpt"
    ln -s chatgpt "$out/bin/codex-desktop"

    install -Dm644 usr/share/applications/chatgpt.desktop \
      "$out/share/applications/chatgpt.desktop"
    substituteInPlace "$out/share/applications/chatgpt.desktop" \
      --replace-fail "Exec=chatgpt %U" "Exec=$out/bin/chatgpt %U"
    install -Dm644 usr/share/pixmaps/chatgpt.png \
      "$out/share/pixmaps/chatgpt.png"

    runHook postInstall
  '';

  meta = {
    description = "Official OpenAI ChatGPT desktop app with Codex, repackaged from the Linux .deb";
    homepage = "https://developers.openai.com/codex/app";
    license = lib.licenses.unfree;
    mainProgram = "chatgpt";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
