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
  writeText,
  bash,
  git,
  ripgrep,
  ncurses,
  zlib,
  release,
  bridgeRelease,
  codexReleases,
  sdkRelease,
  mobilePlugin,
}:
let
  manifest = lib.importJSON ./package.json;
  codexArchive =
    lib.findFirst
      (asset: lib.hasPrefix "dsh-codex-native-" asset.name && lib.hasSuffix ".tgz" asset.name)
      (throw "No packaged DSH Codex Native release is available")
      (
        lib.concatMap (release: release.assets) (
          lib.filter (release: !release.draft) (lib.importJSON codexReleases)
        )
      );
  localeManifest = writeText "rdsh-locale-ja-package.json" (
    builtins.toJSON (
      lib.recursiveUpdate (lib.importJSON "${mobilePlugin}/packages/rdsh-locale-ja/package.json") {
        dsh.bundle.patch = "./cordis.patch.yml";
        peerDependencies."@deepseek-ai/dsh-client-locale" = (lib.importJSON release).version;
      }
    )
  );
  cjkManifest = writeText "rdsh-markdown-cjk-package.json" (
    builtins.toJSON {
      name = "rdsh-markdown-cjk";
      version = (lib.importJSON "${mobilePlugin}/package.json").version;
      type = "module";
      license = "MIT";
      exports."." = "./index.js";
      dsh.bundle.patch = "./cordis.patch.yml";
    }
  );
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
    git
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    ncurses
    zlib
  ];
  autoPatchelfIgnoreMissingDeps = [ "libc.musl-x86_64.so.1" ];

  postPatch = ''
    test '${manifest.dependencies."@deepseek-ai/dsh"}' = '${(lib.importJSON release).version}'
    test '${manifest.dependencies.dsh-claude-bridge}' = '${(lib.importJSON bridgeRelease).version}'
    test '${manifest.dependencies.dsh-codex-native}' = '${codexArchive.browser_download_url}'
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
    localeRoot="$out/lib/deepseek-harness/node_modules/rdsh-locale-ja"
    cp -r ${mobilePlugin}/packages/rdsh-locale-ja "$localeRoot"
    chmod u+w "$localeRoot"
    cp --remove-destination ${localeManifest} "$localeRoot/package.json"
    cat > "$localeRoot/cordis.patch.yml" <<'EOF'
    - insert:
        - id: rdsh-locale-ja
          name: rdsh-locale-ja
          config: {}
    EOF
    cjkRoot="$out/lib/deepseek-harness/node_modules/rdsh-markdown-cjk"
    mkdir -p "$cjkRoot"
    cp ${cjkManifest} "$cjkRoot/package.json"
    cp ${mobilePlugin}/packages/dsh-mobile-maxxing/lib/markdown-cjk.js "$cjkRoot/index.js"
    cp ${mobilePlugin}/packages/dsh-mobile-maxxing/lib/markdown-cjk-runtime.js "$cjkRoot/"
    cp ${mobilePlugin}/LICENSE "$cjkRoot/"
    patch --fuzz=0 -d "$cjkRoot" -p1 < ${./markdown-cjk-assets.patch}
    cat > "$cjkRoot/cordis.patch.yml" <<'EOF'
    - insert:
        - id: rdsh-markdown-cjk
          name: rdsh-markdown-cjk
          config: {}
    EOF
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
    ${lib.getExe nodejs} --expose-internals ${./test-runtime.mjs} "$out/lib/deepseek-harness/node_modules"
    localeCheck="$TMPDIR/dsh-locale-check"
    cp -r ${mobilePlugin} "$localeCheck"
    chmod -R u+w "$localeCheck"
    git init --quiet --initial-branch=main "$localeCheck"
    ${lib.getExe nodejs} "$localeCheck/tools/build-client.mjs" --check
    ${lib.getExe nodejs} --test "$localeCheck/packages/rdsh-locale-ja/test/stage2.test.mjs"
    DSH_ORIG_BIN="$out/lib/deepseek-harness/node_modules/@deepseek-ai/dsh/lib/bin.js" \
      ${lib.getExe nodejs} --test \
      ${mobilePlugin}/packages/dsh-mobile-maxxing/tests/markdown-cjk.test.mjs \
      ${mobilePlugin}/packages/dsh-mobile-maxxing/tests/markdown-cjk-plugin.test.mjs
    export DSH_HOME="$TMPDIR/dsh-install-check"
    "$out/bin/dsh" plugin --profile web add \
      --offline --ignore-scripts --config.auto-install-peers=false \
      link:"$out/lib/deepseek-harness/node_modules/dsh-claude-bridge" \
      link:"$out/lib/deepseek-harness/node_modules/dsh-mobile-maxxing" \
      link:"$out/lib/deepseek-harness/node_modules/rdsh-markdown-cjk" \
      link:"$out/lib/deepseek-harness/node_modules/rdsh-locale-ja" \
      link:"$out/lib/deepseek-harness/node_modules/dsh-codex-native"
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
      exec node ${./update-lock.mjs} ${release} ${bridgeRelease} ${sdkRelease} ${codexReleases} "$@"
    '';
  };

  meta = {
    description = "DeepSeek Harness prerelease with Claude, ChatGPT, Japanese and mobile plugins";
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
