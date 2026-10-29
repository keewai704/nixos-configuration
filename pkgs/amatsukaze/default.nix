{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  unzip,
  artifacts,
}:
let
  candidates = lib.filter (
    artifact:
    !artifact.expired
    && artifact.workflow_run.head_branch == "master"
    && artifact.workflow_run.head_repository_id == artifact.workflow_run.repository_id
    && builtins.match "Amatsukaze_linux_r[0-9]+" artifact.name != null
    && artifact.digest != null
  ) (lib.importJSON artifacts).artifacts;
  revision = artifact: lib.toInt (lib.removePrefix "Amatsukaze_linux_r" artifact.name);
  artifact =
    if candidates == [ ] then
      throw "No current Amatsukaze Linux master build found"
    else
      lib.head (
        lib.sort (
          a: b: if revision a == revision b then a.id > b.id else revision a > revision b
        ) candidates
      );
  version = lib.removePrefix "Amatsukaze_linux_" artifact.name;
in
stdenv.mkDerivation {
  pname = "amatsukaze";
  inherit version;
  src = fetchurl {
    name = "Amatsukaze_linux_${version}_x64.tar.xz.zip";
    url = "https://nightly.link/rigaya/Amatsukaze/actions/artifacts/${toString artifact.id}.zip";
    sha256 = lib.removePrefix "sha256:" artifact.digest;
  };
  sourceRoot = ".";
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    unzip
  ];
  buildInputs = [ stdenv.cc.cc.lib ];
  unpackPhase = ''
    runHook preUnpack
    unzip -p "$src" 'Amatsukaze_linux_${version}_x64.tar.xz' | tar --extract --xz
    runHook postUnpack
  '';
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
      --prefix PATH : "$target/exe_files" \
      --prefix LD_LIBRARY_PATH : "$target/exe_files/lib"
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
    grep -F 'Automated MPEG2-TS Transcoder' cli-help.txt
    grep -F -- '--chapter' cli-help.txt
    printf '%s\n' 'BlankClip(length=30, width=64, height=64, fps=30, pixel_type="YV12", audio_rate=48000, channels=2, sample_type="16bit")' > blank.avs
    LD_LIBRARY_PATH="$out/libexec/amatsukaze/exe_files/lib" \
      $out/libexec/amatsukaze/exe_files/chapter_exe -v "$PWD/blank.avs" -o "$PWD/blank.chapter.txt"
    test -s blank.chapter.txt
    runHook postInstallCheck
  '';
  meta = {
    description = "Amatsukaze CLI with automatic logo generation and AviSynth filters";
    homepage = "https://github.com/rigaya/Amatsukaze";
    changelog = "https://github.com/rigaya/Amatsukaze/commit/${artifact.workflow_run.head_sha}";
    license = lib.licenses.mit;
    mainProgram = "AmatsukazeCLI";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
