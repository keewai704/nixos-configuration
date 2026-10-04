{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  libgcc,
  libx11,
  libxi,
  libxkbcommon,
  at-spi2-core,
  ffmpeg,
  grim,
  wtype,
  xdotool,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "cua-driver";
  version = "0.30.1";

  src = fetchurl {
    url = "https://github.com/trycua/cua/releases/download/cua-driver-rs-v${finalAttrs.version}/cua-driver-rs-${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = "sha256-4yUy043soOcUj6FbopFoaxqKTR07xZ/VEgM4krounEE=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    libgcc
    libx11
    libxi
    libxkbcommon
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/cua-driver $out/bin
    cp -r . $out/libexec/cua-driver/
    makeWrapper $out/libexec/cua-driver/cua-driver $out/bin/cua-driver \
      --set-default CUA_DRIVER_RS_ENABLE_WAYLAND 1 \
      --set-default CUA_DRIVER_RS_TELEMETRY_ENABLED 0 \
      --suffix PATH : ${
        lib.makeBinPath [
          at-spi2-core
          ffmpeg
          grim
          wtype
          xdotool
        ]
      }
    runHook postInstall
  '';

  meta = {
    description = "Cua Driver computer-use runtime and MCP server";
    homepage = "https://github.com/trycua/cua";
    license = lib.licenses.mit;
    mainProgram = "cua-driver";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
