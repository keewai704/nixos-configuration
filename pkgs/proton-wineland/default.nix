{
  lib,
  stdenvNoCC,
  fetchzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "proton-wineland";
  version = "11.0-20260930";

  src = fetchzip {
    url = "https://github.com/nanomatters/proton-cachyos/releases/download/wineland-${finalAttrs.version}/proton-wineland-${finalAttrs.version}-x86_64.tar.xz";
    hash = "sha256-JgJKkOfAmMZHG3h54ZMAcPJXf/Y2c5wOkFjjgpWdkF0=";
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  outputs = [
    "out"
    "steamcompattool"
  ];

  installPhase = ''
    runHook preInstall

    echo "${finalAttrs.pname} should be used through programs.steam.extraCompatPackages." > $out

    mkdir $steamcompattool
    ln -s $src/* $steamcompattool
    rm $steamcompattool/compatibilitytool.vdf
    cp $src/compatibilitytool.vdf $steamcompattool

    runHook postInstall
  '';

  preFixup = ''
    substituteInPlace "$steamcompattool/compatibilitytool.vdf" \
      --replace-fail '"display_name" "proton-wineland-${finalAttrs.version}-x86_64"' '"display_name" "Proton Wineland"' \
      --replace-fail "proton-wineland-${finalAttrs.version}-x86_64" "proton-wineland"
  '';

  meta = {
    description = "Wayland-native Proton build based on proton-cachyos";
    homepage = "https://github.com/nanomatters/proton-cachyos";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
