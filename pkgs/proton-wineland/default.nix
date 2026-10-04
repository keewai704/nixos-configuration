{
  lib,
  stdenvNoCC,
  fetchurl,
  release,
}:
let
  pkgbuild = builtins.readFile "${release}/PKGBUILD";
  field = regex: builtins.head (builtins.match ".*\n${regex}\n.*" ("\n" + pkgbuild));
  version = field "_srctag=([^\n]+)";
  toolName = "proton-wineland-${version}-x86_64";
in
stdenvNoCC.mkDerivation {
  pname = "proton-wineland";
  inherit version;

  src = fetchurl {
    url = "https://github.com/nanomatters/proton-cachyos/releases/download/wineland-${version}/${toolName}.tar.xz";
    sha256 = field "sha256sums=\\('([0-9a-f]{64})'[^\n]*";
  };

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  outputs = [
    "out"
    "steamcompattool"
  ];

  installPhase = ''
    runHook preInstall

    echo "proton-wineland should be used through programs.steam.extraCompatPackages." > $out

    cp -a . $steamcompattool
    substituteInPlace "$steamcompattool/compatibilitytool.vdf" \
      --replace-fail '"display_name" "${toolName}"' '"display_name" "Proton Wineland"' \
      --replace-fail "${toolName}" "proton-wineland"

    runHook postInstall
  '';

  meta = {
    description = "Wayland-native Proton build based on proton-cachyos";
    homepage = "https://github.com/nanomatters/proton-cachyos";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
