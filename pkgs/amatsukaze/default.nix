{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  releases,
}:
let
  release = lib.importJSON releases;
  version = release.tag_name;
  asset = lib.findFirst (
    asset: asset.name == "Amatsukaze_linux_${version}_x64.tar.xz"
  ) (throw "Amatsukaze ${version} has no Linux x64 archive") release.assets;
in
stdenv.mkDerivation {
  pname = "amatsukaze";
  inherit version;
  src = fetchurl {
    url = asset.browser_download_url;
    sha256 = lib.removePrefix "sha256:" asset.digest;
  };
  sourceRoot = ".";
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [ stdenv.cc.cc.lib ];
  dontBuild = true;
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    target="$out/libexec/amatsukaze"
    mkdir -p "$target/exe_files/lib" "$out/bin"
    cp -R JL "$target/"
    cp -R exe_files/plugins64 "$target/exe_files/"
    cp -P exe_files/lib/libavisynth.so* "$target/exe_files/lib/"
    for executable in AmatsukazeCLI AmatsukazeGenLogo chapter_exe join_logo_scp timelineeditor MP4Box; do
      install -m755 "exe_files/$executable" "$target/exe_files/"
    done
    install -m755 exe_files/libAmatsukaze.so "$target/exe_files/"
    chmod -R u+w "$target"
    makeWrapper "$target/exe_files/AmatsukazeCLI" "$out/bin/AmatsukazeCLI" \
      --prefix PATH : "$target/exe_files"
    makeWrapper "$target/exe_files/AmatsukazeGenLogo" "$out/bin/AmatsukazeGenLogo"
    runHook postInstall
  '';
  preFixup = ''
    addAutoPatchelfSearchPath "$out/libexec/amatsukaze/exe_files/lib"
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/AmatsukazeGenLogo --version
    status=0
    $out/bin/AmatsukazeCLI >cli-help.txt 2>&1 || status=$?
    test "$status" = 1
    grep -F 'Automated MPEG2-TS Transcoder ${version}' cli-help.txt
    grep -F -- '--chapter' cli-help.txt
    runHook postInstallCheck
  '';
  meta = {
    description = "Amatsukaze CLI with automatic logo generation and AviSynth filters";
    homepage = "https://github.com/rigaya/Amatsukaze";
    changelog = release.html_url;
    license = lib.licenses.mit;
    mainProgram = "AmatsukazeCLI";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
