{
  lib,
  appimageTools,
  fetchurl,
  makeWrapper,
  release,
  claude-code,
  codex,
  gh,
  git,
}:
let
  pkgbuild = builtins.readFile "${release}/PKGBUILD";
  field = regex: builtins.head (builtins.match ".*\n${regex}\n.*" ("\n" + pkgbuild));
  pname = "t3code";
  version = builtins.replaceStrings [ "_nightly." ] [ "-nightly." ] (field "pkgver=([^\n]+)");
  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
    sha256 = field "sha256sums=\\(\n  '([0-9a-f]{64})'[^\n]*";
  };
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  nativeBuildInputs = [ makeWrapper ];

  extraInstallCommands = ''
    wrapProgram $out/bin/${pname} \
      --prefix PATH : ${
        lib.makeBinPath [
          claude-code
          codex
          gh
          git
        ]
      }
    install -Dm644 ${contents}/*.desktop $out/share/applications/${pname}.desktop
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=${pname}'
    cp -r ${contents}/usr/share/icons $out/share/icons
  '';

  meta = {
    description = "Minimal web GUI for coding agents";
    homepage = "https://github.com/pingdotgg/t3code";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
