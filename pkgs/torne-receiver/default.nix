{
  lib,
  stdenv,
  pkg-config,
  libusb1,
  pcsclite,
  upstream,
}:
stdenv.mkDerivation {
  pname = "torne-receiver";
  version = "0-unstable-${upstream.shortRev}";
  src = upstream;
  patches = [
    ./fast-control.patch
    ./pcsc-socket.patch
  ];
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    libusb1
    pcsclite
  ];
  postPatch = ''
    cp ${./receiver.c} receiver.c
    cp ${./card-socket.h} card-socket.h
  '';
  buildPhase = ''
    runHook preBuild
    $CC -std=gnu11 -O2 -Wall -Wextra -Wno-unused-parameter -pthread \
      -I. -Idriver $(pkg-config --cflags libusb-1.0) receiver.c \
      driver/torne_bridge.c driver/torne_dib.c driver/torne_card.c \
      $(pkg-config --libs libusb-1.0) -o torne-receiver
    $CC -std=gnu11 -O2 -Wall -Wextra -Wno-unused-parameter -fPIC -shared -pthread \
      -I. -Idriver $(pkg-config --cflags libpcsclite) ifd/ifd_torne.c -o libifd_torne.so
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 torne-receiver $out/bin/torne-receiver
    install -Dm755 libifd_torne.so $out/lib/libifd_torne.so
    install -Dm644 LICENSE $out/share/licenses/torne-receiver/LICENSE
    install -Dm644 NOTICE $out/share/licenses/torne-receiver/NOTICE
    runHook postInstall
  '';
  meta = {
    description = "Persistent direct USB driver for Sony CECH-ZD1 J";
    homepage = "https://github.com/mihalinn/torne_drv";
    license = lib.licenses.gpl2Only;
    mainProgram = "torne-receiver";
    platforms = lib.platforms.linux;
  };
}
