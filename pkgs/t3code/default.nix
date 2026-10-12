{
  lib,
  stdenv,
  appimageTools,
  autoPatchelfHook,
  fetchurl,
  makeWrapper,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  gtk4,
  libdrm,
  libgbm,
  libGL,
  libnotify,
  libpulseaudio,
  libsecret,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  libxshmfence,
  libx11,
  nspr,
  nss,
  pango,
  pipewire,
  systemd,
  vulkan-loader,
  zlib,
  release,
  claude-code,
  codex,
  gh,
  git,
}:
let
  pkgbuild = builtins.readFile "${release}/PKGBUILD";
  field = regex: builtins.head (builtins.match ".*\n${regex}\n.*" ("\n" + pkgbuild));
  pname = "t3code";
  version = builtins.replaceStrings [ "_nightly." ] [ "-nightly." ] (field "pkgver=([^\n]+)");
  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
    sha256 = field "sha256sums=\\(\n  '([0-9a-f]{64})'[^\n]*";
  };
  contents = appimageTools.extract { inherit pname version src; };
in
stdenv.mkDerivation {
  inherit pname version;
  src = contents;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    gtk4
    libdrm
    libgbm
    libGL
    libnotify
    libpulseaudio
    libsecret
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    libxshmfence
    libx11
    nspr
    nss
    pango
    pipewire
    stdenv.cc.cc.lib
    systemd
    vulkan-loader
    zlib
  ];

  runtimeDependencies = [
    libGL
    libnotify
    libpulseaudio
    libsecret
    pipewire
    systemd
  ];

  autoPatchelfIgnoreMissingDeps = [ "libc.musl-x86_64.so.1" ];
  dontWrapGApps = true;
  dontStrip = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/t3code $out/bin
    cp -r . $out/libexec/t3code/
    rm -r $out/libexec/t3code/usr/lib
    ln -sf ${vulkan-loader}/lib/libvulkan.so.1 $out/libexec/t3code/libvulkan.so.1
    install -Dm644 ${contents}/*.desktop $out/share/applications/${pname}.desktop
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=${pname}'
    cp -r ${contents}/usr/share/icons $out/share/icons
    runHook postInstall
  '';

  preFixup = ''
    makeWrapper $out/libexec/t3code/t3code $out/bin/${pname} \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${
        lib.makeBinPath [
          claude-code
          codex
          gh
          git
        ]
      }
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ELECTRON_RUN_AS_NODE=1 $out/bin/${pname} -p 'process.versions.electron'
    runHook postInstallCheck
  '';

  meta = {
    description = "Minimal web GUI for coding agents";
    homepage = "https://github.com/pingdotgg/t3code";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
