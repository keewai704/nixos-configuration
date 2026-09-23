{
  lib,
  stdenvNoCC,
  fetchzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-core-subagent";
  version = "1.3.55";

  src = fetchzip {
    url = "https://registry.npmjs.org/@arhen/pi-core-subagent/-/pi-core-subagent-${finalAttrs.version}.tgz";
    hash = "sha256-mcGjdGhI1CLgDwGTH2Y28WaO2r9ww3scEZEStBMxg8w=";
  };

  patches = [ ./lifecycle.patch ];
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r package.json src LICENSE README.md "$out/"
    runHook postInstall
  '';

  meta = {
    description = "Pi core subagents with preserved worktrees and synchronized cancellation";
    homepage = "https://github.com/arhen/pi-extensions/tree/main/packages/core/pi-core-subagent";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
