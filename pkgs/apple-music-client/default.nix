{
  lib,
  rustPlatform,
  src,
  authService,
  python3,
  fetchurl,
  autoPatchelfHook,
  stdenv,
  pkg-config,
  clang,
  cmake,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  fontconfig,
  libxkbcommon,
  libx11,
  libxcb,
  wayland,
  vulkan-loader,
  libglvnd,
  noto-fonts-cjk-sans-static,
  mpv,
  ffmpeg,
  systemd,
}:
let
  python = python3.withPackages (
    ps:
    let
      dataclass-click = ps.buildPythonPackage {
        pname = "dataclass-click";
        version = "1.0.4";
        format = "wheel";
        src = fetchurl {
          url = "https://files.pythonhosted.org/packages/86/dc/38a94a2eb5f756724a6dc87a7aea38f7b747fe7b2e9daabc34a65e6cd9ac/dataclass_click-1.0.4-py3-none-any.whl";
          sha256 = "a225d30c04e4abbdba411cc3d5ec0a2ea829e1dca6500afe5f87cc243e5ead72";
        };
        dependencies = [ ps.click ];
        pythonImportsCheck = [ "dataclass_click" ];
      };
      gamdl = ps.buildPythonPackage {
        pname = "gamdl";
        version = "3.8.5";
        format = "wheel";
        src = fetchurl {
          url = "https://files.pythonhosted.org/packages/42/79/490cc6e0528d38e5d6d89e6b0c6ad9643383436acc836f3de13765a077fc/gamdl-3.8.5-cp310-abi3-manylinux_2_34_x86_64.whl";
          sha256 = "2c0b382d352fad74cef9f35296909f4ab70b11b90d31221e353a372ad97159ff";
        };
        nativeBuildInputs = [ autoPatchelfHook ];
        buildInputs = [ stdenv.cc.cc.lib ];
        dependencies = with ps; [
          async-lru
          click
          colorama
          dataclass-click
          httpx
          httpx-retries
          inquirerpy
          m3u8
          mutagen
          pillow
          pywidevine
          structlog
          yt-dlp
        ];
        pythonImportsCheck = [ "gamdl.cli.cli" ];
      };
    in
    [ gamdl ]
  );
in
rustPlatform.buildRustPackage {
  pname = "apple-music-client";
  version = "0.2.0-${src.shortRev}";
  inherit src;
  cargoLock.lockFile = "${src}/Cargo.lock";

  nativeBuildInputs = [
    pkg-config
    clang
    cmake
    rustPlatform.bindgenHook
    makeWrapper
    copyDesktopItems
  ];
  buildInputs = [
    fontconfig
    libxkbcommon
    libx11
    libxcb
    wayland
  ];
  nativeCheckInputs = [ ffmpeg ];
  cargoTestFlags = [ "--lib" ];

  desktopItems = [
    (makeDesktopItem {
      name = "alac-room-native";
      desktopName = "ALAC Room";
      comment = "Apple Music client";
      exec = "alac-room-native";
      icon = "multimedia-player";
      categories = [
        "AudioVideo"
        "Audio"
        "Player"
      ];
    })
  ];

  postInstall = ''
    mkdir -p "$out/share/alac-room"
    cp -r amclient "$out/share/alac-room/"
    mv "$out/bin/siora" "$out/bin/alac-room-native"
    wrapProgram "$out/bin/alac-room-native" \
      --prefix PATH : ${
        lib.makeBinPath [
          mpv
          ffmpeg
          systemd
          authService
        ]
      } \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          vulkan-loader
          libglvnd
          wayland
          libxkbcommon
          fontconfig
          libx11
          libxcb
        ]
      } \
      --set ALAC_ROOM_PYTHON ${python}/bin/python3 \
      --prefix PYTHONPATH : "$out/share/alac-room" \
      --set-default ALAC_ROOM_FONT_DIR ${noto-fonts-cjk-sans-static}/share/fonts
    PYTHONPATH="$out/share/alac-room" ${python}/bin/python3 -m amclient.gamdl_runner --quality lossless -- --help >/dev/null
  '';

  meta = {
    description = "Native Linux Apple Music client (ALAC Room)";
    homepage = "https://github.com/keewai704/apple-music-client";
    license = lib.licenses.mit;
    mainProgram = "alac-room-native";
    platforms = [ "x86_64-linux" ];
  };
}
