{
  stdenvNoCC,
  fetchzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-subagents-resources";
  version = "0.68.0";

  src = fetchzip {
    url = "https://registry.npmjs.org/pi-subagents/-/pi-subagents-${finalAttrs.version}.tgz";
    hash = "sha256-z9xqUgU3VsVPf2JE8ygMcy4nQA8p+7AWybW/Vmvs5Es=";
  };

  patches = [ ./council-mode.patch ];
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R skills docs agents prompts "$out/"
    substituteInPlace "$out/prompts/council.md" \
      --replace-fail 'skills/council-mode/SKILL.md' "$out/skills/council-mode/SKILL.md" \
      --replace-fail 'skills/pi-subagents/references/execution-controls.md' "$out/skills/pi-subagents/references/execution-controls.md"
    runHook postInstall
  '';
})
