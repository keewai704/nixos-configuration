{
  lib,
  stdenv,
  cmake,
  ninja,
  pkg-config,
  autoconf,
  automake,
  libtool,
  dos2unix,
  python3,
  which,
  runtimeShell,
  upstream,
}:
stdenv.mkDerivation {
  pname = "mirakc-arib";
  version = "0-unstable-${upstream.shortRev}";
  src = upstream;
  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    autoconf
    automake
    libtool
    dos2unix
    python3
    which
  ];
  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail 'git checkout -f && ' "" \
      --replace-fail 'ProcessorCount(NPROC)' 'set(NPROC $ENV{NIX_BUILD_CORES})'
    cat > scripts/tag-or-hash <<'SH'
    #!${runtimeShell}
    printf '%s\n' vendored
    SH
  '';
  cmakeFlags = [
    "-DMIRAKC_ARIB_TEST=ON"
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  ];
  buildPhase = ''
    runHook preBuild
    cmake --build . --target vendor --parallel "$NIX_BUILD_CORES"
    cmake --build . --parallel "$NIX_BUILD_CORES"
    runHook postBuild
  '';
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    bin/mirakc-arib-test
    CI=1 sh ../test/cli_tests.sh "$PWD/bin/mirakc-arib"
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 bin/mirakc-arib $out/bin/mirakc-arib
    runHook postInstall
  '';
  meta = {
    description = "ARIB transport-stream tools for mirakc";
    homepage = "https://github.com/mirakc/mirakc-arib";
    license = lib.licenses.gpl2Plus;
    mainProgram = "mirakc-arib";
    platforms = lib.platforms.linux;
  };
}
