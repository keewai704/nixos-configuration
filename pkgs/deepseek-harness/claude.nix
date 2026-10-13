{
  lib,
  buildDshBundle,
  importNpmLock,
  dsh-kernel,
  src,
}:
let
  manifest = lib.importJSON "${src}/package.json";
in
buildDshBundle {
  pname = manifest.name;
  inherit (manifest) version;
  inherit src;
  patches = [ ./tool-messages.patch ];

  postUnpack = ''
    mv "$sourceRoot" dsh-claude-plugin
    sourceRoot=dsh-claude-plugin
  '';

  npmDeps = importNpmLock { npmRoot = src; };
  npmConfigHook = importNpmLock.npmConfigHook;
  npmFlags = [ "--ignore-scripts" ];
  npmBuildScript = "build";
  linkKernelNodeModules = dsh-kernel;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    npm test -- --maxWorkers=2
    runHook postCheck
  '';

  postInstall = ''
    rm -rf "$out/lib/node_modules/dsh-claude-plugin/node_modules/@deepseek-ai"
  '';

  meta = {
    description = "Claude Agent SDK model adapter for DeepSeek Harness";
    homepage = "https://github.com/snowan/dsh-claude-plugin";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
