{
  lib,
  rustPlatform,
  git,
  coreutils,
  upstream,
  swaggerUi,
}:
rustPlatform.buildRustPackage {
  pname = "mirakc";
  version = (builtins.fromTOML (builtins.readFile (upstream + "/mirakc/Cargo.toml"))).package.version;
  src = upstream;
  cargoLock = {
    lockFile = upstream + "/Cargo.lock";
    allowBuiltinFetchGit = true;
  };
  nativeBuildInputs = [ git ];
  postPatch = ''
    substituteInPlace mirakc-core/tests/config.yml mirakc-core/tests/config.toml \
      --replace-fail /bin/true ${coreutils}/bin/true
  '';
  preConfigure = ''
    cp ${swaggerUi} "$TMPDIR/swagger-ui.zip"
    chmod u+w "$TMPDIR/swagger-ui.zip"
    export SWAGGER_UI_DOWNLOAD_URL="file://$TMPDIR/swagger-ui.zip"
  '';
  env = {
    VERGEN_GIT_SHA = upstream.rev;
    VERGEN_GIT_BRANCH = "release";
  };
  cargoBuildFlags = [
    "-p"
    "mirakc"
  ];
  cargoTestFlags = [
    "-p"
    "mirakc"
    "-p"
    "mirakc-core"
  ];
  postInstall = ''
    install -Dm644 resources/strings.yml $out/share/mirakc/strings.yml
  '';
  meta = {
    description = "Mirakurun-compatible tuner server";
    homepage = "https://github.com/mirakc/mirakc";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "mirakc";
    platforms = lib.platforms.linux;
  };
}
