{
  lib,
  stdenv,
  buildNpmPackage,
  autoPatchelfHook,
  makeWrapper,
  nodejs,
  pnpm_11,
  prefetch-npm-deps,
  writeShellApplication,
  bash,
  git,
  ripgrep,
  zlib,
  release,
  bridgeRelease,
  sdkRelease,
  mobilePlugin,
}:
let
  manifest = lib.importJSON ./package.json;
in
buildNpmPackage {
  pname = "deepseek-harness";
  version = (lib.importJSON release).version;
  src = lib.cleanSource ./.;
  npmDepsHash = lib.trim (builtins.readFile ./npm-deps-hash);
  npmFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    zlib
  ];
  autoPatchelfIgnoreMissingDeps = [ "libc.musl-x86_64.so.1" ];

  postPatch = ''
    test '${manifest.dependencies."@deepseek-ai/dsh"}' = '${(lib.importJSON release).version}'
    test '${manifest.dependencies.dsh-claude-bridge}' = '${(lib.importJSON bridgeRelease).version}'
    test '${
      manifest.dependencies."@anthropic-ai/claude-agent-sdk"
    }' = '${(lib.importJSON sdkRelease).version}'
  '';

  postConfigure = ''
    patch --fuzz=0 -d node_modules/dsh-claude-bridge -p1 < ${./claude-bridge-compat.patch}
    substituteInPlace node_modules/node-addon-require-builtin/lib/index.js \
      --replace-fail 'return api.requireBuiltin(moduleId);' 'return require(moduleId);'
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/deepseek-harness" "$out/bin"
    cp -r node_modules "$out/lib/deepseek-harness/"
    cp -r ${mobilePlugin} "$out/lib/deepseek-harness/node_modules/dsh-mobile-maxxing"
    makeWrapper ${lib.getExe nodejs} "$out/bin/dsh" \
      --add-flags --expose-internals \
      --add-flags "$out/lib/deepseek-harness/node_modules/@deepseek-ai/dsh/lib/bin.js" \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          git
          pnpm_11
          ripgrep
        ]
      }
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/dsh" --version | grep -Fx '${(lib.importJSON release).version}'
    ${lib.getExe nodejs} ${./test-runtime.mjs} "$out/lib/deepseek-harness/node_modules"
    export DSH_HOME="$TMPDIR/dsh-install-check"
    "$out/bin/dsh" plugin --profile web add \
      --offline --ignore-scripts --config.auto-install-peers=false \
      link:"$out/lib/deepseek-harness/node_modules/dsh-claude-bridge" \
      link:"$out/lib/deepseek-harness/node_modules/dsh-mobile-maxxing"
    "$out/bin/dsh" --profile web --dump-config > "$TMPDIR/dsh-composed.yml"
    runHook postInstallCheck
  '';

  passthru.updateScript = writeShellApplication {
    name = "update-deepseek-harness-lock";
    runtimeInputs = [
      nodejs
      prefetch-npm-deps
    ];
    text = ''
      exec node ${./update-lock.mjs} ${release} ${bridgeRelease} ${sdkRelease} "$@"
    '';
  };

  meta = {
    description = "DeepSeek Harness prerelease with Claude Agent SDK and mobile plugins";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = with lib.licenses; [
      mit
      unfree
    ];
    mainProgram = "dsh";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
  };
}
