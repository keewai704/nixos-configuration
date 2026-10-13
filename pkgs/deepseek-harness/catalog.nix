{
  lib,
  dsh-workspace,
  nodejs-slim,
  patch,
}:
dsh-workspace.overrideAttrs (old: {
  pname = "dsh-config-catalog";
  outputs = [ "out" ];
  inherit (dsh-workspace) pnpmDeps;
  patches = [ ];
  postPatch = "";
  dontNpmBuild = true;
  doCheck = true;
  doInstallCheck = true;
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ patch ];
  buildPhase = ''
    runHook preBuild
    node --import tsx ${./catalog}/build.mjs "$PWD" ${dsh-workspace.src} \
      "$TMPDIR/catalog.json" ${
        lib.escapeShellArgs [
          dsh-workspace.src.rev
          dsh-workspace.src.outputHash
        ]
      }
    cp ${./catalog/vitest.config.mjs} catalog-vitest.config.mjs
    runHook postBuild
  '';
  checkPhase = ''
    runHook preCheck
    node node_modules/vitest/vitest.mjs run --config catalog-vitest.config.mjs
    runHook postCheck
  '';
  preInstall = "";
  postInstall = "";
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/share/dsh-config"
    cp "$TMPDIR/catalog.json" "$out/share/dsh-config/catalog.json"
    cp ${./catalog/cli.mjs} "$out/share/dsh-config/cli.mjs"
    makeWrapper ${lib.getExe nodejs-slim} "$out/bin/dsh-config-catalog" \
      --add-flags "$out/share/dsh-config/cli.mjs"
    runHook postInstall
  '';
  installCheckPhase = ''
    runHook preInstallCheck
    DSH_CATALOG_PACKAGE="$out" node --test ${./catalog/tests/cli.test.mjs}
    runHook postInstallCheck
  '';
  disallowedReferences = (old.disallowedReferences or [ ]) ++ [
    dsh-workspace.src
    dsh-workspace.pnpmDeps
  ];
  passthru = { };
  meta = old.meta // {
    description = "Build-time developer catalog of pinned DeepSeek Harness plugin configuration";
    mainProgram = "dsh-config-catalog";
  };
})
