{
  lib,
  stdenv,
  pkg-config,
  pcsclite,
  upstream,
}:
stdenv.mkDerivation {
  pname = "b25-decoder";
  version = "2.10-${upstream.shortRev or "unstable"}";
  src = upstream;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ pcsclite ];

  postPatch = ''
    substituteInPlace B25Decoder/BonProject/TsDescrambler.cpp \
      --replace-fail 'if(!pHalDevice->GetTotalDeviceNum())throw __LINE__;' '#ifdef _WIN32
        if(!pHalDevice->GetTotalDeviceNum())throw __LINE__;' \
      --replace-fail 'if(pHalDevice->GetActiveDeviceNum() >= pHalDevice->GetTotalDeviceNum())throw __LINE__;' 'if(pHalDevice->GetActiveDeviceNum() >= pHalDevice->GetTotalDeviceNum())throw __LINE__;
    #endif'
  '';

  enableParallelBuilding = true;
  makeFlags = [
    "-C"
    "B25Decoder"
    "USE_SIMD=y"
  ];

  installPhase = ''
    runHook preInstall
    install -Dm644 B25Decoder/B25Decoder.so "$out/lib/edcb/B25Decoder.so"
    runHook postInstall
  '';

  meta = {
    description = "PC/SC B-CAS decoder plugin for native Linux EDCB";
    homepage = "https://github.com/tsukumijima/Multi2Dec";
    license = lib.licenses.unfree;
    platforms = lib.platforms.linux;
  };
}
