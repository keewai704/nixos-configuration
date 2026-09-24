{
  lib,
  buildNpmPackage,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./package.json);
in
buildNpmPackage {
  pname = "pi-claude-bridge";
  version = manifest.dependencies.pi-claude-bridge;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
    ];
  };
  npmDepsHash = "sha256-DpwAmeAx0jUtTOWFBnKrc7hzyM2TSXJWacMd+iHc8tc=";
  npmFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
    "--omit=optional"
  ];
  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib"
    cp -r node_modules "$out/lib/"
    runHook postInstall
  '';

  postInstall = ''
    patch -p1 -d "$out/lib/node_modules/pi-claude-bridge" < ${./native-runtime.patch}
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    cd "$out/lib"
    node --input-type=module -e '
      await import("@anthropic-ai/claude-agent-sdk");
      await import("@modelcontextprotocol/sdk/server/mcp.js");
      await import("cc-session-io");
      await import("change-case");
    '
    runHook postInstallCheck
  '';

  meta = {
    description = "Pi Claude Code bridge with pinned runtime dependencies";
    homepage = "https://github.com/elidickinson/pi-claude-bridge";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
