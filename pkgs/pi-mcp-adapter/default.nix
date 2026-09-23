{
  lib,
  buildNpmPackage,
  autoPatchelfHook,
  stdenv,
  zlib,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./package.json);
in
buildNpmPackage {
  pname = "pi-mcp-adapter";
  version = manifest.dependencies.pi-mcp-adapter;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
    ];
  };
  npmDepsHash = "sha256-OUZht6K4kBJFkS05vZBlDK6oNrbkMzERqfNmgVNgNSk=";
  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];
  dontNpmBuild = true;
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    stdenv.cc.cc.lib
    zlib
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib"
    cp -r node_modules "$out/lib/"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    node -e 'require(process.argv[1])' "$out/lib/node_modules/@napi-rs/keyring"
    node -e 'const result = require(process.argv[1]).checkSync("^a+$", ""); if (result.status !== "safe") throw new Error(JSON.stringify(result));' \
      "$out/lib/node_modules/recheck"
    runHook postInstallCheck
  '';

  meta = {
    description = "Pi MCP adapter with pinned runtime dependencies";
    homepage = "https://github.com/nicobailon/pi-mcp-adapter";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
