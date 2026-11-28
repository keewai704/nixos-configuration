{
  lib,
  buildNpmPackage,
  importNpmLock,
  makeWrapper,
  nodejs_22,
  upstream,
}:
buildNpmPackage {
  pname = "browser-control-mcp";
  version = (lib.importJSON "${upstream}/mcp-server/package.json").version;

  src = upstream;
  sourceRoot = "source/mcp-server";

  nodejs = nodejs_22;
  npmDeps = importNpmLock { npmRoot = "${upstream}/mcp-server"; };
  npmConfigHook = importNpmLock.npmConfigHook;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/browser-control-mcp $out/bin
    cp -r dist node_modules package.json $out/lib/browser-control-mcp/
    makeWrapper ${lib.getExe nodejs_22} $out/bin/browser-control-mcp \
      --add-flags $out/lib/browser-control-mcp/dist/server.js
    runHook postInstall
  '';

  meta = {
    description = "MCP server paired with the Browser Control MCP Firefox extension";
    homepage = "https://github.com/eyalzh/browser-control-mcp";
    license = lib.licenses.mit;
    mainProgram = "browser-control-mcp";
  };
}
