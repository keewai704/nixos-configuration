{
  lib,
  stdenvNoCC,
  stdenv,
  fetchzip,
  autoPatchelfHook,
  alsa-lib,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-codex-conversion-helpers";
  version = "3.0.34";

  src = fetchzip {
    url = "https://registry.npmjs.org/@howaboua/pi-codex-conversion/-/pi-codex-conversion-${finalAttrs.version}.tgz";
    hash = "sha256-f6lsazAU31HkSpkyqW0Tw+FSInAHPl/8NZ07xitwxB8=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    stdenv.cc.cc.lib
    alsa-lib
  ];
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 src/tools/apply-patch/bin/linux-x64/apply_patch "$out/bin/apply_patch"
    install -Dm755 src/tools/exec/bin/linux-x64/exec_bridge "$out/bin/exec_bridge"
    install -Dm755 src/tools/view-image/bin/linux-x64/view_image "$out/bin/view_image"
    install -Dm755 src/voice/bin/linux-x64/pi-codex-voice "$out/bin/pi-codex-voice"
    install -Dm644 LICENSE "$out/share/licenses/pi-codex-conversion/LICENSE"
    runHook postInstall
  '';

  meta = {
    description = "NixOS-compatible native helpers for the unmodified Pi Codex conversion extension";
    homepage = "https://github.com/IgorWarzocha/howaboua-pi-stuff/tree/main/packages/pi-codex-conversion";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
})
