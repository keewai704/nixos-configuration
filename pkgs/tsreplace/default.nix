{
  lib,
  stdenv,
  meson,
  ninja,
  pkg-config,
  ffmpeg,
  upstream,
}:
stdenv.mkDerivation {
  pname = "tsreplace";
  version = "0-unstable-${upstream.shortRev}";
  src = upstream;
  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ];
  buildInputs = [ ffmpeg.dev ];
  postPatch = ''
    substituteInPlace meson.build \
      --replace-fail 'git rev-list HEAD | wc -l' 'printf %s ${toString upstream.revCount}'
  '';
  mesonFlags = [
    "-Dlibav_static=false"
    "-Dstatic_runtime=false"
  ];
  doCheck = true;
  meta = {
    description = "Replace only the video in MPEG-TS while preserving broadcast data";
    homepage = "https://github.com/rigaya/tsreplace";
    license = lib.licenses.mit;
    mainProgram = "tsreplace";
    platforms = lib.platforms.linux;
  };
}
