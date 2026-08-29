{
  autoPatchelfHook,
  fetchurl,
  lib,
  libXi,
  libx11,
  libxkbcommon,
  stdenv,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "cua-driver";
  version = "0.22.1";

  src = fetchurl {
    url = "https://github.com/trycua/cua/releases/download/cua-driver-rs-v${finalAttrs.version}/cua-driver-rs-${finalAttrs.version}-linux-x86_64-binary.tar.gz";
    hash = "sha256-QY1LQV8ZHVx7G71oLtAgnJjwvWokAa8s2AZjTvJwxUs=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

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
    ln -s ../lib/cua-driver/cua-driver "$out/bin/cua-driver"

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
