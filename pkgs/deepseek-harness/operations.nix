{
  lib,
  buildDshBundle,
  dsh-kernel,
  dsh-workspace,
  webBundle,
  baseBundle,
  claudeBundle,
  subscriptionsBundle,
  symlinkJoin,
  python3,
  util-linux,
}:
let
  webRoot = "${webBundle}/lib/node_modules/@deepseek-ai/dsh-web-app";
  kernelRoot = "${dsh-kernel}/lib/deepseek-harness";
  testModules = symlinkJoin {
    name = "dsh-node-modules";
    paths = [
      "${baseBundle}/lib/node_modules"
      "${webBundle}/lib/node_modules"
      "${webRoot}/node_modules"
      "${kernelRoot}/node_modules"
    ];
  };
in
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
    testRoot="$TMPDIR/operations-check/pkgs/deepseek-harness/operations"
    mkdir -p "$testRoot"
    cp -r "$src"/. "$testRoot/"
    chmod -R u+w "$TMPDIR/operations-check"
    export DSH_TEST_KERNEL=${kernelRoot}
    export DSH_TEST_WEB=${webRoot}
    export DSH_CHECKPOINT_TEST_MODULES=${kernelRoot}
    export DSH_LOCALE_UPSTREAM=${dsh-workspace.src}
    export DSH_TEST_SOURCE=${dsh-workspace.src}
    export DSH_TEST_ADAPTER_PATCHES=${
      lib.escapeShellArg (
        builtins.toJSON [
          "${claudeBundle}/lib/node_modules/dsh-claude-plugin/cordis.patch.yml"
          "${subscriptionsBundle}/lib/node_modules/dsh-plugin-subscriptions/cordis.patch.yml"
        ]
      )
    }
    export DSH_RETENTION_FLOCK=${util-linux}/bin/flock
    export DSH_RETENTION_CATALOG=${kernelRoot}/node_modules/@deepseek-ai/dsh-session-format-catalog/lib/index.js
    export DSH_RETENTION_NODE_MODULES=${testModules}
    export DSH_MIGRATE_FLOCK=${util-linux}/bin/flock
    export DSH_MIGRATE_PINNED_SOURCE=${dsh-workspace.src}
    export DSH_MIGRATE_NODE_MODULES=${testModules}
    node --check "$testRoot/client.js"
    node --test "$testRoot"/core.test.mjs "$testRoot"/journal.test.mjs \
      "$testRoot"/privacy-*.test.mjs "$testRoot"/message-policy.test.mjs \
      "$testRoot"/budget*.test.mjs "$testRoot"/checkpoint*.test.mjs \
      "$testRoot"/composition.test.mjs "$testRoot"/schedule-recovery-web.test.mjs \
      "$testRoot"/locale-ja.test.mjs "$testRoot"/maintenance.test.mjs "$testRoot"/migrate*.test.mjs
    python3 "$testRoot/launch-lock.test.py"
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    target="$out/lib/node_modules/@keewai/dsh-operations"
    mkdir -p "$target/node_modules/@deepseek-ai"
    python3 - "$src" "$target" <<'PY'
    from pathlib import Path
    import shutil
    import sys
    source, target = map(Path, sys.argv[1:])
    for item in source.iterdir():
        if item.is_file() and item.suffix == ".mjs" and not item.name.endswith(".test.mjs") and not item.name.startswith("build-") and not item.name.startswith("plan-client-"):
            shutil.copyfile(item, target / item.name)
    shutil.copyfile(source / "package.json", target / "package.json")
    PY
    node "$src/build-client.mjs" "$target/client.js"
    node "$src/build-composition.mjs" ${dsh-workspace.src} ${kernelRoot} "$target/cordis.patch.yml"
    ln -s ${webRoot}/node_modules/@deepseek-ai/dsh-client-product-analytics \
      "$target/node_modules/@deepseek-ai/dsh-client-product-analytics"
    runHook postInstall
  '';
  meta = {
    description = "Persistent DSH privacy, budgets, checkpoints and authenticated operations";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}).overrideAttrs
  {
    src = ./operations;
    disallowedReferences = [ ];
  }
