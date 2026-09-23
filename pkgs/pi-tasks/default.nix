{
  lib,
  stdenvNoCC,
  fetchzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-tasks";
  version = "0.9.0";

  src = fetchzip {
    url = "https://registry.npmjs.org/@tintinweb/pi-tasks/-/pi-tasks-${finalAttrs.version}.tgz";
    hash = "sha256-9mTixVJ37vG8w1RK6frUlRfXTi/7oApiAj5P1o98jh0=";
  };

  patches = [ ./tracking-only.patch ];
  dontConfigure = true;
  dontBuild = true;

  postPatch = ''
    substituteInPlace package.json --replace-fail '"./src/index.ts"' '"./index.ts"'
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r src package.json LICENSE README.md "$out/"
    cp ${./index.ts} "$out/index.ts"
    runHook postInstall
  '';

  meta = {
    description = "Pi TODO tracking without subagent execution";
    homepage = "https://github.com/tintinweb/pi-tasks";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
