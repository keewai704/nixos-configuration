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
    cp ${./tui/main.rs} src/main.rs
    mkdir src/tui
    cp ${./tui/mod.rs} src/tui/mod.rs
    cp ${./tui/browse.rs} src/tui/browse.rs
    cp ${./tui/queue.rs} src/tui/queue.rs
    cp ${./tui/controls.rs} src/tui/controls.rs
    cp ${./tui/cover.rs} src/tui/cover.rs
    cp ${./tui/mouse.rs} src/tui/mouse.rs
    cp ${./tui/events.rs} src/tui/events.rs
    cp ${./tui/navigation.rs} src/tui/navigation.rs
    cp ${./tui/playback.rs} src/tui/playback.rs
    cp ${./tui/settings.rs} src/tui/settings.rs
    cp ${./tui/render.rs} src/tui/render.rs
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
