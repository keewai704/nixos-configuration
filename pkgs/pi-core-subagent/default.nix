{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "pi-core-subagent";
  version = "1.3.55";

  src = fetchFromGitHub {
    owner = "keewai704";
    repo = "pi-extensions";
    rev = "275252976c01990e83666eabe63429e0cde05ad5";
    hash = "sha256-vlU+oVjFHk+N+M/A9RjQ/xh0bNAzuIovkSRnI7C2icE=";
  };
  sourceRoot = "source/packages/core/pi-core-subagent";
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
    homepage = "https://github.com/keewai704/pi-extensions/tree/main/packages/core/pi-core-subagent";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
