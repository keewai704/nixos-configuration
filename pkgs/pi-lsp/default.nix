{
  lib,
  stdenvNoCC,
  fetchzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-lsp";
  version = "0.49.7";

  src = fetchzip {
    url = "https://registry.npmjs.org/@narumitw/pi-lsp/-/pi-lsp-${finalAttrs.version}.tgz";
    hash = "sha256-v6NQ311vtZl2x0PAEkGCIDzR3IixEd1t0Bg5h3jzM9E=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r package.json src dist docs LICENSE README.md "$out/"
    runHook postInstall
  '';

  meta = {
    description = "Pi language server protocol tools";
    homepage = "https://github.com/narumiruna/pi-extensions/tree/main/packages/pi-lsp";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
