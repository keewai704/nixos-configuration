{
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
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
  stdenv,
  systemd,
  trash-cli,
  vulkan-loader,
  xdg-utils,
  xz,
}:

let
  version = "26.825.41651";
  runtimeLibraries = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
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
    libx11.dev
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
    hash = "sha256-IbIulcDEOj8RTz7TJpKr7cY49AV6CPmMmINuLT6aZx4=";
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
    # Optional prebuilt modules for non-glibc Linux variants are not loaded on
    # this x86_64 glibc package.
    "libc.musl-x86_64.so.1"

    # These optional KDE shims are loaded only when a matching Qt desktop is
    # detected. Pulling Qt 5 and Qt 6 into one derivation would conflict.
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

    cat > "$out/lib/chatgpt/launch-chatgpt" <<'EOF'
    #!${lib.getExe bash}
    set -euo pipefail

    export PATH="${
      lib.makeBinPath [
        coreutils
        git
        glib
        trash-cli
        xdg-utils
      ]
    }''${PATH:+:$PATH}"

    sourceResources="@out@/lib/chatgpt/resources"
    sourceMarketplace="$sourceResources/plugins/openai-bundled"
    cacheHome="''${XDG_CACHE_HOME:-$HOME/.cache}"
    cacheRoot="$cacheHome/chatgpt/bundled-plugin-resources/@version@-resources-v1"
    marker="$cacheRoot/.source"
    cachedSource=""
    if [[ -L "$marker" ]]; then
      cachedSource="$(readlink "$marker")"
    fi

    # Nix store files are intentionally read-only. The app patches bundled
    # plugin manifests while materializing them, so provide a versioned resource
    # overlay with writable plugins and immutable siblings linked from the store.
    if [[ -d "$cacheRoot" && "$cachedSource" != "$sourceResources" ]]; then
      rm -rf "$cacheRoot"
    fi

    if [[ "$cachedSource" != "$sourceResources" ]]; then
      cacheParent="''${cacheRoot%/*}"
      mkdir -p "$cacheParent"
      staging="$(mktemp -d "$cacheParent/.@version@.XXXXXX")"
      trap 'rm -rf "$staging"' EXIT

      for resource in "$sourceResources"/*; do
        resourceName="''${resource##*/}"
        if [[ "$resourceName" != plugins ]]; then
          ln -s "$resource" "$staging/$resourceName"
        fi
      done

      mkdir -p "$staging/plugins"
      cp -R "$sourceMarketplace" "$staging/plugins/openai-bundled"
      chmod -R u+rwX "$staging"
      ln -s "$sourceResources" "$staging/.source"

      if mv -T "$staging" "$cacheRoot" 2>/dev/null; then
        trap - EXIT
      fi
    fi

    [[ -L "$marker" && "$(readlink "$marker")" == "$sourceResources" ]]
    export CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH="$cacheRoot"
    exec "@out@/lib/chatgpt/ChatGPT" "$@"
    EOF
    substituteInPlace "$out/lib/chatgpt/launch-chatgpt" \
      --replace-fail '@out@' "$out" \
      --replace-fail '@version@' "$version"
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
