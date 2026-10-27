{
  lib,
  stdenv,
  glibc,
  lua5_2,
  openssl,
  upstream,
}:
stdenv.mkDerivation {
  pname = "edcb";
  version = "10.70-${upstream.shortRev or "unstable"}";
  src = upstream;

  nativeBuildInputs = [ glibc.bin ];
  buildInputs = [ lua5_2 ];

  postPatch = ''
    substituteInPlace Common/PathUtil.h \
      --replace-fail 'L"/var/local/edcb"' 'L"/var/lib/edcb"' \
      --replace-fail 'L"/usr/local/lib/edcb"' 'L"/var/lib/edcb/lib"'
    substituteInPlace Common/TCPServer.cpp \
      --replace-fail 'getaddrinfo(NULL, szPort, &hints, &result)' \
        'getaddrinfo("127.0.0.1", szPort, &hints, &result)'
    substituteInPlace EpgTimerSrv/EpgTimerSrv/Makefile \
      --replace-fail '-llua5.2' '-llua'
    substituteInPlace EpgTimerSrv/EpgTimerSrv/civetweb.c \
      --replace-fail '"libssl.so.3"' '"${lib.getLib openssl}/lib/libssl.so.3"' \
      --replace-fail '"libcrypto.so.3"' '"${lib.getLib openssl}/lib/libcrypto.so.3"'
  '';

  enableParallelBuilding = true;
  makeFlags = [
    "-C"
    "Document/Unix"
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 EpgTimerSrv/EpgTimerSrv/EpgTimerSrv "$out/bin/EpgTimerSrv"
    install -Dm755 EpgDataCap_Bon/EpgDataCap_Bon/EpgDataCap_Bon "$out/bin/EpgDataCap_Bon"
    for tool in asyncbuf relayread tsidmove-edcb tspgtxt; do
      install -Dm755 "Document/Unix/$tool" "$out/bin/$tool"
    done
    install -Dm644 EpgDataCap3/EpgDataCap3/EpgDataCap3_Unicode.so "$out/lib/edcb/EpgDataCap3.so"
    for plugin in RecName_Macro SendTSTCP Write_Default; do
      install -Dm644 "$plugin/$plugin/$plugin.so" "$out/lib/edcb/$plugin.so"
    done

    mkdir -p "$out/share/edcb"
    for ini in Bitrate.ini BonCtrl.ini; do
      iconv -f CP932 -t UTF-8 "ini/$ini" | tr -d '\r' > "$out/share/edcb/$ini"
    done
    sed -i 's/\.dll$/.so/' "$out/share/edcb/BonCtrl.ini"
    tr -d '\r' < ini/ContentTypeText.txt > "$out/share/edcb/ContentTypeText.txt"
    cp -R ini/HttpPublic "$out/share/edcb/"

    runHook postInstall
  '';

  meta = {
    description = "Native Linux BonDriver recording and EPG server from xtne6f's EDCB";
    homepage = "https://github.com/xtne6f/EDCB";
    license = lib.licenses.unfree;
    mainProgram = "EpgTimerSrv";
    platforms = lib.platforms.linux;
  };
}
