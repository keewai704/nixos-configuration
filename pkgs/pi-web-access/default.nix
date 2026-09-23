{
  lib,
  buildNpmPackage,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./package.json);
in
buildNpmPackage {
  pname = "pi-web-access";
  version = manifest.dependencies.pi-web-access;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
    ];
  };
  npmDepsHash = "sha256-d21aBC7szigjfE+w/ALeyfAKHGYZyTQJJwOsvgZCuNU=";
  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];
  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib"
    cp -r node_modules "$out/lib/"
    runHook postInstall
  '';

  meta = {
    description = "Pi web access extension with pinned runtime dependencies";
    homepage = "https://github.com/nicobailon/pi-web-access";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
