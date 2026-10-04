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
  manifest = builtins.readFile release;
  field = name: builtins.head (builtins.match ".*\n${name}: ([^\n]+)\n.*" ("\n" + manifest));
  pname = "t3code";
  version = field "version";
  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/${field "path"}";
    hash = "sha512-${field "sha512"}";
  };
  contents = appimageTools.extractType2 { inherit pname version src; };
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
