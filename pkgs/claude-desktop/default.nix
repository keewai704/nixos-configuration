{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libayatana-appindicator,
  libcap_ng,
  libdrm,
  libgbm,
  libglvnd,
  libnotify,
  libpulseaudio,
  libseccomp,
  libsecret,
  libuuid,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  libxshmfence,
  libxtst,
  nspr,
  nss,
  pango,
  pipewire,
  systemd,
  vulkan-loader,
  bubblewrap,
  claude-code,
  git,
  nodejs,
  socat,
  xdg-utils,
  releases,
}:
let
  records = map (
    record:
    lib.listToAttrs (
      lib.filter (field: field != null) (
        map (
          line:
          let
            field = builtins.match "(Package|Version|Architecture|Filename|SHA256): (.*)" line;
          in
          if field == null then null else lib.nameValuePair (builtins.head field) (builtins.elemAt field 1)
        ) (lib.splitString "\n" record)
      )
    )
  ) (lib.splitString "\n\n" (builtins.readFile releases));
  candidates = lib.filter (
    record: record.Package or "" == "claude-desktop" && record.Architecture or "" == "amd64"
  ) records;
  release = lib.last (lib.sort (a: b: lib.versionOlder a.Version b.Version) candidates);
in
stdenv.mkDerivation {
  pname = "claude-desktop";
  version = release.Version;

  src = fetchurl {
    url = "https://downloads.claude.ai/claude-desktop/apt/stable/${release.Filename}";
    sha256 = release.SHA256;
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libayatana-appindicator
    libcap_ng
    libdrm
    libgbm
    libglvnd
    libnotify
    libpulseaudio
    libseccomp
    libsecret
    libuuid
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    libxshmfence
    libxtst
    nspr
    nss
    pango
    pipewire
    stdenv.cc.cc.lib
    systemd
    vulkan-loader
  ];

  runtimeDependencies = [
    libglvnd
    libsecret
    libnotify
    libpulseaudio
    pipewire
    vulkan-loader
  ];

  dontBuild = true;
  dontStrip = true;
  dontWrapGApps = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --fsys-tarfile $src | tar -x --no-same-owner --no-same-permissions
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec $out/share
    cp -r usr/lib/claude-desktop $out/libexec/
    cp -r usr/share/applications usr/share/icons $out/share/
    rm $out/libexec/claude-desktop/chrome-sandbox
    substituteInPlace $out/share/applications/com.anthropic.Claude.desktop \
      --replace-fail 'Exec=claude-desktop' "Exec=$out/bin/claude-desktop"
    runHook postInstall
  '';

  postFixup = ''
    makeWrapper $out/libexec/claude-desktop/claude-desktop $out/bin/claude-desktop \
      "''${gappsWrapperArgs[@]}" \
      --set CLAUDE_CODE_LOCAL_BINARY ${lib.getExe claude-code} \
      --prefix PATH : ${
        lib.makeBinPath [
          bubblewrap
          claude-code
          git
          nodejs
          socat
          xdg-utils
        ]
      } \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          libglvnd
          vulkan-loader
        ]
      } \
      --add-flags '--ozone-platform-hint=auto --password-store=gnome-libsecret'
  '';

  meta = {
    description = "Official Claude Desktop Linux application";
    homepage = "https://claude.ai/download";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "claude-desktop";
  };
}
