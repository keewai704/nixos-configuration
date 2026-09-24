{
  lib,
  stdenv,
  fetchFromGitHub,
}:
stdenv.mkDerivation {
  pname = "ohook-wine";
  version = "0.4";

  src = fetchFromGitHub {
    owner = "asdcorp";
    repo = "ohook";
    rev = "85916041ad8a96794dd8dd4690ec59af9686d759";
    hash = "sha256-JVAXfSe0xqmEdgXdOA8vxFiH8AJLG9Sj/pKGRk6B6lQ=";
  };

  patches = [ ./ohook-wine.patch ];
  prePatch = ''
    substituteInPlace sppc.c sppc.def sppcs64.def --replace-fail $'\r' ""
  '';
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    ${stdenv.cc.targetPrefix}dlltool -k -d sppcs64.def -l libsppcs64.a
    ${stdenv.cc.targetPrefix}windres --codepage=65001 sppc.rc sppc64.res.o
    $CC -Os -Wall -Werror -fno-ident -municode -nostartfiles -nostdlib \
      -shared sppc.c sppc.def sppc64.res.o -o sppc.dll -L. \
      -lsppcs64 -lkernel32 -lshlwapi -ladvapi32 \
      -Wl,-eDllMain,--exclude-all-symbols,--enable-stdcall-fixup,--dynamicbase,--nxcompat,--subsystem,windows:6.0
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 sppc.dll "$out/share/wine4office/sppc.dll"
    runHook postInstall
  '';

  meta = {
    description = "Ohook with Wine compatibility for installed Office product keys";
    homepage = "https://github.com/asdcorp/ohook";
    license = lib.licenses.mit;
  };
}
