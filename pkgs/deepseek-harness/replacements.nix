{
  lib,
  buildDshBundle,
  dsh-workspace,
  dsh-kernel,
  nodejs-slim,
  patch,
}:
let
  compiled = dsh-workspace.overrideAttrs (old: {
    pname = "dsh-reliability-plugins-build";
    outputs = [ "out" ];
    patches = old.patches or [ ];
    dontNpmBuild = true;
    doCheck = true;
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ patch ];
    buildPhase = ''
      runHook preBuild
      node ${./replacements}/build.mjs ${dsh-workspace.src} "$PWD" "$PWD/node_modules" "$TMPDIR/reliability"
      runHook postBuild
    '';
    checkPhase = ''
      runHook preCheck
      DSH_REPLACEMENTS_BUNDLE="$TMPDIR/reliability" \
        DSH_REPLACEMENTS_NATIVE_PEERS=${dsh-kernel}/lib/deepseek-harness/node_modules \
        node ${./replacements}/verify.mjs ${dsh-workspace.src} "$PWD" "$TMPDIR/reliability-test"
      node ${./replacements}/acp/verify.mjs ${dsh-workspace.src} \
        ${dsh-kernel}/lib/deepseek-harness/node_modules "$PWD/node_modules" \
        "$PWD/packages/subagent/subagent-acp/node_modules/@agentclientprotocol/sdk"
      node ${./replacements}/installed-import.mjs "$TMPDIR/reliability" \
        ${dsh-kernel}/lib/deepseek-harness/node_modules "$TMPDIR/reliability-installed-check"
      runHook postCheck
    '';
    preInstall = "";
    postInstall = "";
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r "$TMPDIR/reliability"/{lib,package.json,LICENSE} "$out/"
      runHook postInstall
    '';
    disallowedReferences = [ nodejs-slim ];
  });
in
(buildDshBundle.fromWorkspace {
  pname = "dsh-reliability";
  version = "0.1.0";
  packageName = "@keewai/dsh-reliability";
  inherit dsh-kernel dsh-workspace;
  linkKernelNodeModules = dsh-kernel;
  nativeBuildInputs = [ patch ];
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    node --input-type=module - "$out/lib/node_modules/@keewai/dsh-reliability" <<'JS'
    import { pathToFileURL } from 'node:url';
    import path from 'node:path';
    for (const entry of ['workflow', 'schedule', 'subagents', 'acp', 'approval', 'approval-journal']) {
      await import(pathToFileURL(path.join(process.argv[2], 'lib', entry + '.js')));
    }
    console.log('All installed replacement entry points import with kernel peers only');
    JS
    runHook postInstallCheck
  '';
  installPhase = ''
    runHook preInstall
    target="$out/lib/node_modules/@keewai/dsh-reliability"
    mkdir -p "$target"
    cp -r ${compiled}/{lib,package.json,LICENSE} "$target/"
    chmod u+w "$target/package.json"
    node --input-type=module - "$target" <<'JS'
    import fs from 'node:fs';
    import path from 'node:path';
    const root = process.argv[2];
    const file = path.join(root, 'package.json');
    const manifest = JSON.parse(fs.readFileSync(file, 'utf8'));
    manifest.dsh = { bundle: { patch: './cordis.patch.yml' } };
    manifest.exports['./cordis.patch.yml'] = './cordis.patch.yml';
    fs.writeFileSync(file, JSON.stringify(manifest, null, 2) + '\n');
    fs.writeFileSync(path.join(root, 'cordis.patch.yml'), '[]\n');
    JS
    runHook postInstall
  '';
  meta = {
    description = "Independent DSH workflow, scheduling, subagent and approval implementations";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}).overrideAttrs
  {
    src = ./replacements;
    disallowedReferences = [ ];
  }
