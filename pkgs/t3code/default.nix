{
  lib,
  stdenv,
  appimageTools,
  asar,
  autoPatchelfHook,
  fetchurl,
  makeWrapper,
  python3,
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
  upstream,
  claude-code,
  gh,
  git,
  tailscale,
}:
let
  sourceInfo = map lib.trim (lib.splitString "\n" (builtins.readFile (upstream + "/.SRCINFO")));
  sourceValue =
    key:
    lib.removePrefix "${key} = " (
      lib.findFirst (lib.hasPrefix "${key} = ") (throw "T3 Code nightly metadata has no ${key}")
        sourceInfo
    );
  pname = "t3code";
  version = lib.replaceStrings [ "_" ] [ "-" ] (sourceValue "pkgver");
  appImageName = "T3-Code-${version}-x86_64.AppImage";
  appImageUrl = "https://github.com/pingdotgg/t3code/releases/download/v${version}/${appImageName}";
  src =
    assert sourceValue "source" == "${appImageName}::${appImageUrl}";
    fetchurl {
      url = appImageUrl;
      sha256 = sourceValue "sha256sums";
    };
  contents = appimageTools.extract { inherit pname version src; };
in
stdenv.mkDerivation {
  inherit pname version;
  src = contents;

  nativeBuildInputs = [
    asar
    autoPatchelfHook
    makeWrapper
    python3
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

  postPatch = ''
    asar extract resources/app.asar app
    python3 ${./web-subpath.py} app
    asar pack app resources/app.asar --unpack-dir node_modules
    rm -r app
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/t3code $out/bin
    cp -r . $out/libexec/t3code/
    rm -r $out/libexec/t3code/usr/lib
    ln -sf ${vulkan-loader}/lib/libvulkan.so.1 $out/libexec/t3code/libvulkan.so.1
    runHook postInstall
  '';

  preFixup = ''
    wrapperArgs=(
      "''${gappsWrapperArgs[@]}"
      --set T3CODE_DISABLE_AUTO_UPDATE true
      --prefix PATH : ${
        lib.makeBinPath [
          claude-code
          gh
          git
          tailscale
        ]
      }
    )
    makeWrapper $out/libexec/t3code/t3code $out/bin/t3 "''${wrapperArgs[@]}" \
      --set ELECTRON_RUN_AS_NODE 1 \
      --set T3CODE_CLI_PATH $out/bin/t3 \
      --add-flags $out/libexec/t3code/resources/app.asar/apps/server/dist/bin.mjs
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ELECTRON_RUN_AS_NODE=1 $out/libexec/t3code/t3code -p 'process.versions.electron'
    $out/bin/t3 --version | grep -F '${version}'
    asar extract $out/libexec/t3code/resources/app.asar t3code-install-check
    ELECTRON_RUN_AS_NODE=1 $out/libexec/t3code/t3code ${./test-web-subpath.mjs} \
      "$PWD/t3code-install-check"
    ELECTRON_RUN_AS_NODE=1 $out/libexec/t3code/t3code ${./test-thread-links.mjs} \
      "$PWD/t3code-install-check/apps/server/dist"
    ELECTRON_RUN_AS_NODE=1 $out/libexec/t3code/t3code ${./test-codex-recovery.mjs} \
      "$PWD/t3code-install-check/apps/server/dist"
    runHook postInstallCheck
  '';

  meta = {
    description = "T3 Code nightly headless server and CLI for coding agents";
    homepage = "https://github.com/pingdotgg/t3code";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "t3";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
