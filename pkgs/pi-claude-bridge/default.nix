{
  lib,
  buildNpmPackage,
}:
buildNpmPackage {
  pname = "pi-claude-bridge";
  version = "0.8.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
    ];
  };
  npmDepsHash = "sha256-uYl84xm6XgEhvFZBVGwTYIBpnKaln8taMezGyxKjYYA=";
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
    homepage = "https://github.com/keewai704/pi-claude-bridge";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
