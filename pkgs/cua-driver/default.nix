{
  autoPatchelfHook,
  fetchurl,
  glib,
  lib,
  libXi,
  libx11,
  libxkbcommon,
  makeWrapper,
  stdenv,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "cua-driver";
  version = "0.22.2";

  src = fetchurl {
    url = "https://github.com/trycua/cua/releases/download/cua-driver-rs-v${finalAttrs.version}/cua-driver-rs-${finalAttrs.version}-linux-x86_64-binary.tar.gz";
    hash = "sha256-zGarwzRPdXP2rzbnQffoKkP9JMXL+dcdg9/7M6DjJQY=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    libXi
    libx11
    libxkbcommon
    stdenv.cc.cc.lib
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/lib/cua-driver"
    tar -xzf "$src" -C "$out/lib/cua-driver" \
      cua-driver \
      cua-cursor-theme \
      wayland-helper
    makeWrapper "$out/lib/cua-driver/cua-driver" "$out/bin/cua-driver" \
      --prefix PATH : ${lib.makeBinPath [ glib ]}

    runHook postInstall
  '';

  meta = {
    description = "Background computer-use driver for AI agents";
    homepage = "https://github.com/trycua/cua/tree/main/libs/cua-driver";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "cua-driver";
  };
})
