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
    appAsar="$out/lib/chatgpt/resources/app.asar"
    chmod u+rw "$appAsar"
    ${python3}/bin/python3 ${./patch-asar.py} "$appAsar"

    cat > "$out/lib/chatgpt/launch-chatgpt" <<'EOF'
    #!${lib.getExe bash}
    set -euo pipefail

    # NixOS exposes the configured GL/DRI driver through this runtime profile.
    # Keep it ahead of the store closure so libGLX can find the active driver;
    # the packaged Mesa/libGL dependencies provide a deterministic fallback.
    export LD_LIBRARY_PATH="/run/opengl-driver/lib:${lib.makeLibraryPath runtimeLibraries}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
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

    # Unlike nixpkgs-wrapped Electron applications, the upstream prebuilt
    # ChatGPT binary does not translate NIXOS_OZONE_WL into Chromium flags.
    # Without these flags it chooses X11/XWayland even in the Wayland session,
    # which bypasses the Wayland text-input protocol used by Fcitx5 for inline
    # preedit. Keep native Wayland opt-in through the existing NixOS variable,
    # and require a live Wayland display so X11 sessions retain the fallback.
    ozoneFlags=()
    if [[ -n "''${NIXOS_OZONE_WL:-}" && -n "''${WAYLAND_DISPLAY:-}" ]]; then
      ozoneFlags=(--ozone-platform=wayland --enable-wayland-ime=true)
    fi

    # User arguments come last so an explicit --ozone-platform=x11 remains a
    # supported escape hatch when native Wayland is unsuitable.
    exec "@out@/lib/chatgpt/ChatGPT" "''${ozoneFlags[@]}" "$@"
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
