{
  lib,
  stdenvNoCC,
  fetchurl,
  zstd,
}:
stdenvNoCC.mkDerivation rec {
  pname = "wine4office-runner";
  version = "0.2.2-beta.1";

  src = fetchurl {
    url = "https://github.com/ttv20/wine4office/releases/download/${version}/wine4office-${version}-x86_64.tar.zst";
    hash = "sha256-Xlhdk36xaxUSvVKaVJTFYT6A/V4G4WzzKTcWVm2V71Q=";
  };

  nativeBuildInputs = [ zstd ];
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -a . "$out/"
    runHook postInstall
  '';

  meta = {
    description = "Office-focused Wine runner for Bottles";
    homepage = "https://github.com/ttv20/wine4office";
    license = lib.licenses.lgpl21Plus;
    platforms = [ "x86_64-linux" ];
  };
}
