{
  lib,
  stdenvNoCC,
  fetchzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-agent-teams";
  version = "0.5.5";

  src = fetchzip {
    url = "https://registry.npmjs.org/@tmustier/pi-agent-teams/-/pi-agent-teams-${finalAttrs.version}.tgz";
    hash = "sha256-K47SnrYTBPTCI69KbBfv+6Zs0gICowwWLAWtvSbH8qE=";
  };

  patches = [ ./lifecycle.patch ];
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r package.json extensions skills docs LICENSE README.md "$out/"
    runHook postInstall
  '';

  meta = {
    description = "Pi agent teams with worker messaging and preserved worktrees";
    homepage = "https://github.com/tmustier/pi-agent-teams";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
