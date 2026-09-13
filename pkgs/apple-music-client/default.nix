{
  lib,
  rustPlatform,
  src,
  authService,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  mpv-unwrapped,
  ffmpeg-headless,
  systemd,
}:
rustPlatform.buildRustPackage {
  pname = "apple-music-client";
  version = "0.3.2-tui-${src.shortRev}";
  inherit src;
  cargoLock.lockFile = ./Cargo.lock;

  patches = [ ./terminal-only.patch ];
  postPatch = ''
    rm -r src/app src/app.rs src/icons.rs src/theme.rs amclient assets
    cp ${./Cargo.lock} Cargo.lock
    cp ${./main.rs} src/main.rs
    cp -r ${./tui} src/tui
  '';

  nativeBuildInputs = [
    makeWrapper
    copyDesktopItems
  ];
  nativeCheckInputs = [
    ffmpeg-headless
    mpv-unwrapped
  ];
  cargoTestFlags = [ "--workspace" ];

  desktopItems = [
    (makeDesktopItem {
      name = "siora";
      desktopName = "Siora";
      comment = "Apple Music terminal client";
      exec = "siora";
      terminal = true;
      categories = [
        "AudioVideo"
        "Audio"
        "Player"
        "ConsoleOnly"
      ];
    })
  ];

  postInstall = ''
    wrapProgram "$out/bin/siora" \
      --prefix PATH : ${
        lib.makeBinPath [
          mpv-unwrapped
          ffmpeg-headless
          systemd
          authService
        ]
      }
  '';

  meta = {
    description = "Apple Music terminal client (Siora)";
    homepage = "https://github.com/keewai704/apple-music-client";
    license = lib.licenses.mit;
    mainProgram = "siora";
    platforms = [ "x86_64-linux" ];
  };
}
