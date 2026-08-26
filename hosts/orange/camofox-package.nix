{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  fetchurl,
  patchelf,
  makeWrapper,
  unzip,
  nodejs,
  python3,
  pkg-config,
  gtk3,
  dbus-glib,
  libXt,
  alsa-lib,
  libx11,
  libXcomposite,
  libXcursor,
  libXdamage,
  libXext,
  libXfixes,
  libXi,
  libXrandr,
  libXrender,
  libXScrnSaver,
  libXtst,
  mesa,
  libgbm,
  freetype,
  fontconfig,
  pango,
  atk,
  cairo,
  gdk-pixbuf,
  glib,
  dbus,
  libxcb,
  xorg-server,
  x11vnc,
  novnc,
  websockify,
  procps,
  coreutils,
  gawk,
  gnugrep,
  nettools,
  bash,
  which,
  yt-dlp,
}:

let
  camoufoxVersion = "135.0.1";
  camoufoxRelease = "beta.24";

  camoufoxRuntimeLibraries = [
    stdenv.cc.cc.lib
    gtk3
    dbus-glib
    libXt
    alsa-lib
    libx11
    libXcomposite
    libXcursor
    libXdamage
    libXext
    libXfixes
    libXi
    libXrandr
    libXrender
    libXScrnSaver
    libXtst
    mesa
    libgbm
    freetype
    fontconfig
    pango
    atk
    cairo
    gdk-pixbuf
    glib
    dbus
    libxcb
  ];

  camoufox = stdenv.mkDerivation {
    pname = "camoufox-bin";
    version = "${camoufoxVersion}-${camoufoxRelease}";

    src = fetchurl {
      url = "https://github.com/daijro/camoufox/releases/download/v${camoufoxVersion}-${camoufoxRelease}/camoufox-${camoufoxVersion}-${camoufoxRelease}-lin.x86_64.zip";
      hash = "sha256-YeHsRV4CFyCvOKXMX/dWYSE2PLW4K3LyTjgbomdqSIg=";
    };

    nativeBuildInputs = [
      patchelf
      unzip
    ];

    dontUnpack = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/lib/camoufox" "$out/bin"
      unzip -q "$src" -d "$out/lib/camoufox" || test -x "$out/lib/camoufox/camoufox-bin"
      chmod -R u+w "$out/lib/camoufox"
      chmod 0755 "$out/lib/camoufox/camoufox" "$out/lib/camoufox/camoufox-bin"

      # Keep Camoufox's bundled libraries byte-for-byte intact. Rewriting the
      # complete Firefox bundle with autoPatchelf causes an early SIGSEGV.
      # Only the two ELF launchers need Nix's dynamic loader; their runtime
      # libraries are supplied by the outer server wrapper below.
      patchelf --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
        "$out/lib/camoufox/camoufox"
      patchelf --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
        "$out/lib/camoufox/camoufox-bin"

      # camofox-browser's external-bundle contract expects these generated
      # compatibility entries beside properties.json and the browser binary.
      printf '{"version":"%s","release":"%s"}\n' \
        ${lib.escapeShellArg camoufoxVersion} \
        ${lib.escapeShellArg camoufoxRelease} \
        > "$out/lib/camoufox/version.json"
      ln -s fontconfigs/linux "$out/lib/camoufox/fontconfig"
      ln -s ../lib/camoufox/camoufox-bin "$out/bin/camoufox"

      runHook postInstall
    '';

    meta = {
      description = "Prebuilt Camoufox anti-detect browser bundle";
      homepage = "https://github.com/daijro/camoufox";
      license = lib.licenses.mpl20;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "camoufox";
    };
  };
in
buildNpmPackage {
  pname = "camofox-browser";
  version = "1.14.0";

  src = fetchFromGitHub {
    owner = "jo-inc";
    repo = "camofox-browser";
    rev = "e5a36f5cd0332fde6597de474329a308a53a0716";
    hash = "sha256-POVwAiVoScS5c1QMZslz1wbfWttYdeQEy2msxoVt+uk=";
  };

  npmDepsHash = "sha256-J3ggx9bAFClH/fnIQ21gzw66LNFrRFah7K5iwxj/b9I=";
  npmDepsFetcherVersion = 2;
  makeCacheWritable = true;
  npmFlags = [ "--ignore-scripts" ];
  dontBuild = true;
  dontNpmBuild = true;

  nativeBuildInputs = [
    makeWrapper
    pkg-config
    python3
  ];

  postPatch = ''
    # Upstream v1.14.0 documents 0 as "never", but schedules a zero-delay
    # shutdown. Keep the browser/X11/VNC backend alive when explicitly disabled.
    substituteInPlace server.js \
      --replace-fail \
        'if (browserIdleTimer || sessions.size > 0 || !browser) return;' \
        'if (BROWSER_IDLE_TIMEOUT_MS <= 0 || browserIdleTimer || sessions.size > 0 || !browser) return;'
    substituteInPlace plugins/vnc/vnc-watcher.sh \
      --replace-fail 'NOVNC_DIR="/usr/share/novnc"' \
        'NOVNC_DIR="${novnc}/share/webapps/novnc"'
    substituteInPlace camofox.config.json \
      --replace-fail '"vnc": { "enabled": false' \
        '"vnc": { "enabled": true'
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/lib/camofox-browser"

    npm prune --omit=dev
    npm rebuild better-sqlite3 --build-from-source --offline
    find node_modules/better-sqlite3/build/Release -mindepth 1 \
      ! -name better_sqlite3.node \
      -exec rm -rf {} +

    cp -r \
      LICENSE \
      README.md \
      camofox.config.json \
      lib \
      mcp \
      node_modules \
      openapi.json \
      openclaw.plugin.json \
      package.json \
      plugins \
      scripts \
      server.js \
      "$out/lib/camofox-browser/"

    makeWrapper ${lib.getExe nodejs} "$out/bin/camofox-browser" \
      --add-flags "--max-old-space-size=512 $out/lib/camofox-browser/server.js" \
      --chdir "$out/lib/camofox-browser" \
      --set CAMOUFOX_EXECUTABLE ${lib.getExe camoufox} \
      --prefix LD_LIBRARY_PATH : ${camoufox}/lib/camoufox:${lib.makeLibraryPath camoufoxRuntimeLibraries} \
      --prefix PATH : ${
        lib.makeBinPath [
          xorg-server
          x11vnc
          websockify
          procps
          coreutils
          gawk
          gnugrep
          nettools
          bash
          which
          yt-dlp
        ]
      }

    runHook postInstall
  '';

  passthru = {
    inherit camoufox;
  };

  meta = {
    description = "Anti-detection browser server for AI agents";
    homepage = "https://github.com/jo-inc/camofox-browser";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "camofox-browser";
  };
}
