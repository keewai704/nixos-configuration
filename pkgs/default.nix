{ pkgs }:
{
  helium = pkgs.callPackage ./helium { };
  sunshine-display = pkgs.callPackage ./sunshine-display { };
  whisper-ctranslate2-cuda = pkgs.callPackage ./whisper-ctranslate2-cuda { };
}
