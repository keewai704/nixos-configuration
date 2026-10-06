{
  lib,
  stdenv,
  fetchurl,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_11,
  nodejs,
  autoPatchelfHook,
  makeWrapper,
  writeText,
  static-web-server,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "penpot-mcp";
  version = "2.17.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@penpot/mcp/-/mcp-${finalAttrs.version}.tgz";
    hash = "sha256-iSU1DmHdZuyuYi87N7BUE4gWVnLsVpJfn6WQncv3BE0=";
  };

  postPatch = ''
    mv pnpm-lock.dist.yaml pnpm-lock.yaml
    substituteInPlace packages/server/src/PluginBridge.ts \
      --replace-fail 'new WebSocketServer({ port: port })' \
        'new WebSocketServer({
          port: port,
          host: "127.0.0.1",
          verifyClient: (info) =>
            ["localhost", "127.0.0.1", "[::1]"].some((host) => info.req.headers.host === host + ":" + port) &&
            ["http://localhost:4400", "http://127.0.0.1:4400"].includes(info.origin)
        })'
    substituteInPlace packages/server/src/PenpotMcpServer.ts \
      --replace-fail 'await this.replServer.start();' "" \
      --replace-fail 'this.app = express();' 'this.app = express();
        this.app.use((req: any, res: any, next: any) => {
          const validHost = ["localhost", "127.0.0.1", "[::1]"].some((host) => req.headers.host === host + ":" + this.port);
          const origin = req.headers.origin;
          if (!validHost || (origin !== undefined && !["http://localhost:4400", "http://127.0.0.1:4400"].includes(origin))) {
            res.status(403).send("Forbidden");
            return;
          }
          next();
        });'
  '';

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    postPatch = "mv pnpm-lock.dist.yaml pnpm-lock.yaml";
    hash = "sha256-M26hRBuuqu49BSRzYUXro0ILtxi2eXc03lDeKEayFp8=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm_11
    pnpmConfigHook
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [ stdenv.cc.cc.lib ];

  dontAutoPatchelf = true;
  dontPatchELF = true;
  dontStrip = true;

  buildPhase = ''
    runHook preBuild
    pnpm --dir packages/common run build
    pnpm --dir packages/server run build
    WS_URI=http://localhost:4402 pnpm --dir packages/plugin run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    rm -rf node_modules packages/{common,server,plugin}/node_modules
    CI=true pnpm install --offline --frozen-lockfile --prod --ignore-scripts
    mkdir -p "$out/lib/penpot-mcp/packages/server" "$out/share/penpot-mcp/plugin" "$out/bin"
    cp -r node_modules "$out/lib/penpot-mcp/"
    rm "$out/lib/penpot-mcp/node_modules/.pnpm/node_modules/"{mcp-common,mcp-plugin}
    cp -r packages/server/{dist,node_modules,package.json} "$out/lib/penpot-mcp/packages/server/"
    cp -r packages/plugin/dist/. "$out/share/penpot-mcp/plugin/"
    makeWrapper ${lib.getExe nodejs} "$out/bin/penpot-mcp-server" \
      --chdir "$out/lib/penpot-mcp/packages/server/dist" \
      --set PENPOT_MCP_SERVER_HOST 127.0.0.1 \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}" \
      --add-flags "$out/lib/penpot-mcp/packages/server/dist/index.js"
    makeWrapper ${lib.getExe static-web-server} "$out/bin/penpot-mcp-plugin" \
      --add-flags "--host 127.0.0.1 --port 4400 --root $out/share/penpot-mcp/plugin --cors-allow-origins https://design.penpot.app,http://localhost:4400,http://127.0.0.1:4400 --cache-control-headers=false --config-file ${writeText "penpot-mcp-plugin.toml" ''
        [[advanced.headers]]
        source = "**"
        [advanced.headers.headers]
        Cache-Control = "no-cache"
      ''}"
    runHook postInstall
  '';

  postFixup = ''
    addAutoPatchelfSearchPath "$out"
    mapfile -d "" nativeModules < <(find "$out" -name '*.node' -print0)
    autoPatchelf "''${nativeModules[@]}"
  '';

  meta = {
    description = "Local Penpot MCP server and browser plugin";
    homepage = "https://github.com/penpot/penpot/tree/develop/mcp";
    license = lib.licenses.mpl20;
    mainProgram = "penpot-mcp-server";
    platforms = lib.platforms.linux;
  };
})
