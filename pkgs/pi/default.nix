{
  lib,
  buildNpmPackage,
  importNpmLock,
  nodejs,
  python3,
  autoPatchelfHook,
  makeWrapper,
  stdenv,
}:

buildNpmPackage {
  pname = "pi-environment";
  version = "1.2.0";
  src = lib.cleanSource ./.;

  npmDeps = importNpmLock { npmRoot = ./.; };
  npmConfigHook = importNpmLock.npmConfigHook;
  npmFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [ stdenv.cc.cc.lib ];
  dontAutoPatchelf = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/pi" "$out/bin"
    cp -r node_modules "$out/lib/pi/"
    cp web-launch.py "$out/lib/pi/"
    makeWrapper ${lib.getExe nodejs} "$out/bin/pi" \
      --add-flags "$out/lib/pi/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js"
    makeWrapper ${lib.getExe python3} "$out/bin/pi-web-server" \
      --add-flags "$out/lib/pi/web-launch.py" \
      --add-flags "$out" \
      --add-flags ${lib.getExe nodejs}
    runHook postInstall
  '';

  postFixup = ''
    modules="$out/lib/pi/node_modules"
    addAutoPatchelfSearchPath "$modules"
    autoPatchelf \
      "$modules/node-pty/prebuilds/linux-x64/pty.node" \
      "$modules/@next/swc-linux-x64-gnu" \
      "$modules/@img/sharp-linux-x64" \
      "$modules/@img/sharp-libvips-linux-x64"
    HOME="$TMPDIR" "$out/bin/pi" --version
    NODE_PATH="$modules" ${lib.getExe nodejs} -e 'require("node-pty"); require("sharp"); require("@next/swc-linux-x64-gnu")'
  '';

  meta = {
    description = "Pi with pi-web, subscription providers, and standalone Codex web search";
    homepage = "https://github.com/agegr/pi-web";
    license = lib.licenses.mit;
    mainProgram = "pi";
    platforms = [ "x86_64-linux" ];
  };
}
