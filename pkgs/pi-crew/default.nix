{
  lib,
  stdenvNoCC,
  fetchzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-crew";
  version = "1.0.34";

  src = fetchzip {
    url = "https://registry.npmjs.org/@melihmucuk/pi-crew/-/pi-crew-${finalAttrs.version}.tgz";
    hash = "sha256-VICdpdnYu+JdtT2t+4DEARiPkY9kGBVkKBpX17qLU9U=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r package.json extension agents skills prompts docs LICENSE README.md "$out/"
    runHook postInstall
  '';

  meta = {
    description = "Pi subagent crew orchestration";
    homepage = "https://github.com/melihmucuk/pi-crew";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
