{
  fetchurl,
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "karukan-dictionary";
  version = "0.1.0";

  src = fetchurl {
    url = "https://github.com/togatoga/karukan/releases/download/v0.1.0/dict.tgz";
    hash = "sha256-8ZTSUmv4JmIrxbr3wH51Ja2b3i3GOJbNkpBFKDpK7M0=";
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm444 dict.bin "$out/share/karukan-im/dict.bin"
    install -Dm444 docs/LEGAL "$out/share/doc/karukan-dictionary/LEGAL"
    install -Dm444 docs/LICENSE-2.0.txt "$out/share/doc/karukan-dictionary/LICENSE-2.0.txt"
    install -Dm444 docs/README.md "$out/share/doc/karukan-dictionary/README.md"
    runHook postInstall
  '';

  meta = {
    description = "System dictionary for the Karukan Japanese input method";
    homepage = "https://github.com/togatoga/karukan/releases/tag/v0.1.0";
    license = lib.licenses.asl20;
    platforms = lib.platforms.all;
  };
}
