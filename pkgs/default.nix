{ pkgs }:
{
  helium = pkgs.callPackage ./helium { };
  pi = pkgs.callPackage ./pi { };
  sunshine-display = pkgs.callPackage ./sunshine-display { };
  whisper-ctranslate2-cuda = pkgs.callPackage ./whisper-ctranslate2-cuda { };
}
