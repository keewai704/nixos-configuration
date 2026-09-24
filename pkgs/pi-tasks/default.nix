{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "pi-tasks";
  version = "0.9.0";

  src = fetchFromGitHub {
    owner = "keewai704";
    repo = "pi-tasks";
    rev = "83db8c1c5a780f63f55cf3df8ca7ead4eefbd09f";
    hash = "sha256-KpJMY2LWs5YtViwsh/LUbtcoISoQJzYP9ofsfylOGnc=";
  };
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r src index.ts package.json LICENSE README.md "$out/"
    runHook postInstall
  '';

  meta = {
    description = "Pi TODO tracking without subagent execution";
    homepage = "https://github.com/keewai704/pi-tasks";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
