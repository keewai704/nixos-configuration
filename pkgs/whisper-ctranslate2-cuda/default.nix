{
  pkgsCuda,
  python3Packages,
  whisper-ctranslate2,
}:
let
  whisperPythonPackages = python3Packages.overrideScope (
    final: prev: {
      ctranslate2 = prev.ctranslate2.override {
        ctranslate2-cpp = pkgsCuda.ctranslate2;
      };
      faster-whisper = prev.faster-whisper.override {
        ctranslate2 = final.ctranslate2;
      };
    }
  );
in
whisper-ctranslate2.override {
  python3Packages = whisperPythonPackages;
}
