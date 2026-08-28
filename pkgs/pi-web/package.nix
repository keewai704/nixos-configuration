{
  autoPatchelfHook,
  buildNpmPackage,
  git,
  lib,
  makeWrapper,
  nodejs_24,
  ripgrep,
  stdenv,
}:

buildNpmPackage {
  pname = "pi-web";
  version = "0.8.11";

  src = ./.;

  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-WYVm0yeskRs7mFzSFDgCZ0RlzDx2nrj182nv2uQ2bts=";
  dontNpmBuild = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/lib/pi-web"
    cp -r node_modules "$out/lib/pi-web/"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/pi-web" \
      --add-flags "$out/lib/pi-web/node_modules/@agegr/pi-web/bin/pi-web.js" \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          nodejs_24
          ripgrep
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "Local web UI for the Pi coding agent";
    homepage = "https://github.com/agegr/pi-web";
    license = lib.licenses.mit;
    mainProgram = "pi-web";
    platforms = lib.platforms.linux;
  };
}
