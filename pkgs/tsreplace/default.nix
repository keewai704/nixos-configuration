{
  lib,
  stdenv,
  meson,
  ninja,
  pkg-config,
  python3,
  ffmpeg,
  upstream,
}:
stdenv.mkDerivation {
  pname = "tsreplace";
  version = "0-unstable-${upstream.shortRev}";
  src = upstream;
  patches = [
    ./pmt-completeness.patch
    ./eof-video.patch
  ];
  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    python3
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
  postCheck = ''
    python ${./test-pmt.py} "$NIX_BUILD_TOP/$sourceRoot" ${./test-pmt.cpp.in}
    python ${./test-vfr.py} ./tsreplace ${ffmpeg}/bin/ffmpeg ${ffmpeg}/bin/ffprobe
  '';
  meta = {
    description = "Replace only the video in MPEG-TS while preserving broadcast data";
    homepage = "https://github.com/rigaya/tsreplace";
    license = lib.licenses.mit;
    mainProgram = "tsreplace";
    platforms = lib.platforms.linux;
  };
}
