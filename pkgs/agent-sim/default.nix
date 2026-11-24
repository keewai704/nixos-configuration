{
  lib,
  rustPlatform,
  makeWrapper,
  python3,
  boost,
  clang,
  cmake,
  coreutils,
  curl,
  ffmpeg,
  findutils,
  gawk,
  git,
  gnugrep,
  gnused,
  gnutar,
  gzip,
  jq,
  ninja,
  openssl,
  procps,
  util-linux,
  writeShellScript,
  xz,
  upstream,
}:
let
  python = python3.withPackages (ps: [
    ps.dnspython
    ps.numpy
    ps.pillow
  ]);
  runtimePath = [
    python
    clang
    cmake
    coreutils
    curl
    ffmpeg
    findutils
    gawk
    git
    gnugrep
    gnused
    gnutar
    gzip
    jq
    ninja
    openssl
    procps
    util-linux
    xz
  ];
  fixShebangs = writeShellScript "agent-sim-fix-x86sim-shebangs" ''
    for dir in "$@"; do
      [ -d "$dir" ] || continue
      ${lib.getExe gnugrep} -rlZE '^#! ?/bin/bash' "$dir" --exclude-dir=darling |
        ${lib.getExe' findutils "xargs"} -0 -r ${lib.getExe gnused} -i -E '1s|^#! ?/bin/bash|#!/usr/bin/env bash|'
    done
  '';
in
rustPlatform.buildRustPackage {
  pname = "agent-sim";
  version = "0-unstable-${upstream.shortRev}";
  src = upstream;
  cargoLock.lockFile = "${upstream}/Cargo.lock";
  nativeBuildInputs = [ makeWrapper ];
  postPatch = ''
    substituteInPlace scripts/setup-vm.sh \
      --replace-fail 'sudo loginctl enable-linger "$USER"' ':' \
      --replace-fail '	sudo -n true 2>/dev/null; then' '	false; then' \
      --replace-fail '"$X" version' '${fixShebangs} "$ROOT/x86sim-$X86SIM_VERSION/usr/share/x86sim/payload" "$DATA/app/$X86SIM_VERSION"
    "$X" version'
    substituteInPlace scripts/setup-vm.sh scripts/patch-x86sim.sh \
      --replace-fail 'sudo DEBIAN_FRONTEND=noninteractive apt-get' ':'
    substituteInPlace scripts/phone.sh \
      --replace-fail /usr/share/vulkan/icd.d/lvp_icd.json /run/opengl-driver/share/vulkan/icd.d/lvp_icd.x86_64.json
  '';
  postInstall = ''
    cp -r scripts hooks patches $out/
    wrapProgram $out/bin/agent-sim \
      --prefix PATH : ${lib.makeBinPath runtimePath} \
      --prefix CMAKE_PREFIX_PATH : ${lib.getDev boost} \
      --set-default X86SIM_DARLING_MODE userns
  '';
  meta = {
    description = "iOS simulators for AI agents on Linux";
    homepage = "https://github.com/Developing-Gamer/agent-sim";
    license = lib.licenses.asl20;
    mainProgram = "agent-sim";
    platforms = [ "x86_64-linux" ];
  };
}
