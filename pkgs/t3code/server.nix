{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  zlib,
  release,
  claude-code,
  codex,
  gh,
  git,
}:
let
  pkgbuild = builtins.readFile "${release}/PKGBUILD";
  field = regex: builtins.head (builtins.match ".*\n${regex}\n.*" ("\n" + pkgbuild));
  version = builtins.replaceStrings [ "_nightly." ] [ "-nightly." ] (field "pkgver=([^\n]+)");
in
stdenv.mkDerivation {
  pname = "t3code-server";
  inherit version;

  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/t3-${version}-linux-x64.tar.gz";
    sha256 = "e78bf72f95164cfb05a0c8b5001c148fe586475aeaea8d685c2d36b1e2dcc876";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    zlib
  ];
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/t3code $out/bin
    cp -r . $out/lib/t3code/
    makeWrapper $out/lib/t3code/t3 $out/bin/t3 \
      --prefix PATH : ${
        lib.makeBinPath [
          claude-code
          codex
          gh
          git
        ]
      }
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/t3 --version
    runHook postInstallCheck
  '';

  meta = {
    description = "T3 Code nightly server with native coding agents";
    homepage = "https://github.com/pingdotgg/t3code";
    license = lib.licenses.mit;
    mainProgram = "t3";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
