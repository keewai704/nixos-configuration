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
  releases,
  claude-code,
  codex,
  gh,
  git,
  tailscale,
}:
let
  release = lib.findFirst (
    release: !release.draft && lib.hasInfix "-nightly." release.tag_name
  ) (throw "No T3 Code nightly release found") (lib.importJSON releases);
  pname = "t3code";
  version = lib.removePrefix "v" release.tag_name;
  asset = lib.findFirst (
    asset: asset.name == "T3-Code-${version}-x86_64.AppImage"
  ) (throw "T3 Code ${version} has no x86_64 AppImage") release.assets;
  src = fetchurl {
    url = asset.browser_download_url;
    sha256 = lib.removePrefix "sha256:" asset.digest;
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
    install -Dm644 ${contents}/t3code.desktop $out/share/applications/t3code.desktop
    substituteInPlace $out/share/applications/t3code.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=t3code'
    cp -r ${contents}/usr/share/icons $out/share/icons
    runHook postInstall
  '';

  preFixup = ''
    wrapperArgs=(
      "''${gappsWrapperArgs[@]}"
      --set T3CODE_DISABLE_AUTO_UPDATE true
      --prefix PATH : ${
        lib.makeBinPath [
          claude-code
          codex
          gh
          git
          tailscale
        ]
      }
    )
    makeWrapper $out/libexec/t3code/t3code $out/bin/t3code "''${wrapperArgs[@]}"
    makeWrapper $out/libexec/t3code/t3code $out/bin/t3 "''${wrapperArgs[@]}" \
      --set ELECTRON_RUN_AS_NODE 1 \
      --set T3CODE_CLI_PATH $out/bin/t3 \
      --add-flags $out/libexec/t3code/resources/app.asar/apps/server/dist/bin.mjs
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ELECTRON_RUN_AS_NODE=1 $out/bin/t3code -p 'process.versions.electron'
    $out/bin/t3 --version | grep -F '${version}'
    runHook postInstallCheck
  '';

  meta = {
    description = "T3 Code nightly desktop and CLI for coding agents";
    homepage = "https://github.com/pingdotgg/t3code";
    changelog = release.html_url;
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
