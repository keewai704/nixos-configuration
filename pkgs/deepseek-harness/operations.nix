{
  lib,
  buildDshBundle,
  dsh-kernel,
  dsh-workspace,
  python3,
  util-linux,
}:
(buildDshBundle.fromWorkspace {
  pname = "dsh-operations";
  version = "0.1.0";
  packageName = "@keewai/dsh-operations";
  inherit dsh-kernel dsh-workspace;
  linkKernelNodeModules = dsh-kernel;
  nativeCheckInputs = [
    python3
    util-linux
  ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node --check "$src/client.js"
    node --test "$src/core.test.mjs" "$src/journal.test.mjs"
    python3 "$src/launch-lock.test.py"
    testRoot="$TMPDIR/operations-check/pkgs/deepseek-harness/operations"
    mkdir -p "$testRoot"
    cp "$src"/maintenance{,.test}.mjs "$testRoot/"
    DSH_RETENTION_FLOCK=${util-linux}/bin/flock \
      DSH_RETENTION_CATALOG=${dsh-kernel}/lib/deepseek-harness/node_modules/@deepseek-ai/dsh-session-format-catalog/lib/index.js \
      node --test "$testRoot/maintenance.test.mjs"
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    target="$out/lib/node_modules/@keewai/dsh-operations"
    mkdir -p "$target"
    cp "$src"/{package.json,cordis.patch.yml,index.mjs,core.mjs,client.js,journal.mjs,journal-plugin.mjs} "$target/"
    runHook postInstall
  '';
  meta = {
    description = "Authenticated DSH privacy, retention preview and recovery controls";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}).overrideAttrs
  {
    src = ./operations;
    disallowedReferences = [ ];
  }
