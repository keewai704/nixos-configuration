{
  lib,
  rustPlatform,
  git,
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
  env = {
    VERGEN_GIT_SHA = upstream.rev;
    VERGEN_GIT_BRANCH = "release";
    SWAGGER_UI_DOWNLOAD_URL = "file://${swaggerUi}";
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
