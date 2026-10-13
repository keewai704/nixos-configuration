{
  lib,
  buildDshBundle,
  dsh-kernel,
  dsh-workspace,
  webBundle,
}:
(buildDshBundle.fromWorkspace {
  pname = "dsh-ui-plan";
  version = "0.2.1-alpha.2";
  packageName = "@keewai/dsh-ui-plan";
  inherit dsh-kernel dsh-workspace;
  linkKernelNodeModules = dsh-kernel;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/node_modules/@keewai"
    node ${./operations/plan-client-build.mjs} \
      ${webBundle}/lib/node_modules/@deepseek-ai/dsh-web-app/node_modules/@deepseek-ai/dsh-client-ui-plan \
      "$out/lib/node_modules/@keewai/dsh-ui-plan"
    node --input-type=module - "$out/lib/node_modules/@keewai/dsh-ui-plan" <<'JS'
    import fs from 'node:fs';
    import path from 'node:path';
    const root = process.argv[2];
    const file = path.join(root, 'package.json');
    const manifest = JSON.parse(fs.readFileSync(file, 'utf8'));
    manifest.dsh.bundle = { patch: './cordis.patch.yml' };
    manifest.exports['./cordis.patch.yml'] = './cordis.patch.yml';
    fs.writeFileSync(file, JSON.stringify(manifest, null, 2) + '\n');
    fs.writeFileSync(path.join(root, 'cordis.patch.yml'), '[]\n');
    JS
    runHook postInstall
  '';
  meta = {
    description = "Independent DSH plan client with truthful mode guidance";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}).overrideAttrs
  {
    src = ./operations;
    disallowedReferences = [ ];
  }
