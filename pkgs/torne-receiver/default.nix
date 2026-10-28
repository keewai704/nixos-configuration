{
  lib,
  stdenv,
  pkg-config,
  libusb1,
  pcsclite,
  python3,
  upstream,
  bonDriverHeaders,
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
    cp ${./receiver-client.h} receiver-client.h
    cp ${./stream.c} stream.c
    cp ${./stream.h} stream.h
    cp ${./bondriver.cpp} bondriver.cpp
    cp ${./bon-api.h} bon-api.h
  '';
  buildPhase = ''
    runHook preBuild
    $CC -std=gnu11 -O2 -Wall -Wextra -Wno-unused-parameter -pthread \
      -I. -Idriver $(pkg-config --cflags libusb-1.0) receiver.c stream.c \
      driver/torne_bridge.c driver/torne_dib.c driver/torne_card.c \
      $(pkg-config --libs libusb-1.0) -o torne-receiver
    $CC -std=gnu11 -O2 -Wall -Wextra -Wno-unused-parameter -fPIC -shared -pthread \
      -I. -Idriver $(pkg-config --cflags libpcsclite) ifd/ifd_torne.c -o libifd_torne.so
    $CXX -std=c++17 -O2 -Wall -Wextra -Wno-ignored-qualifiers -Wno-missing-field-initializers \
      -fPIC -shared -pthread -I. -isystem ${bonDriverHeaders} bondriver.cpp -ldl -o BonDriver_Torne.so
    runHook postBuild
  '';
  doCheck = true;
  nativeCheckInputs = [ python3 ];
  checkPhase = ''
    runHook preCheck
    $CC -std=gnu11 -O2 -Wall -Wextra -Wno-unused-parameter -I. \
      ${./test-dib.c} -o test-dib
    ./test-dib
    python ${./test-bondriver.py} "$PWD/BonDriver_Torne.so"
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 torne-receiver $out/bin/torne-receiver
    install -Dm755 libifd_torne.so $out/lib/libifd_torne.so
    install -Dm755 BonDriver_Torne.so $out/lib/BonDriver_Torne.so
    install -Dm644 LICENSE $out/share/licenses/torne-receiver/LICENSE
    install -Dm644 NOTICE $out/share/licenses/torne-receiver/NOTICE
    runHook postInstall
  '';
  meta = {
    description = "Persistent USB receiver and native BonDriver2 for Sony CECH-ZD1 J";
    homepage = "https://github.com/mihalinn/torne_drv";
    license = lib.licenses.gpl2Only;
    mainProgram = "torne-receiver";
    platforms = lib.platforms.linux;
  };
}
