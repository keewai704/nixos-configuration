{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "pi-agent-teams";
  version = "0.5.5";

  src = fetchFromGitHub {
    owner = "keewai704";
    repo = "pi-agent-teams";
    rev = "0649c681a62e7743e4190ae10e5016e45f97dbef";
    hash = "sha256-ZLYjYgk2RaBQ0yx0gRp1hgikx0FiuWbiq+0MrBLUfZU=";
  };
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
    homepage = "https://github.com/keewai704/pi-agent-teams";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
