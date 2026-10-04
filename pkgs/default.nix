{ pkgs }:
{
  helium = pkgs.callPackage ./helium { };
  fprintd-cs9711 = pkgs.callPackage ./fprintd-cs9711 { };
  sunshine-display = pkgs.callPackage ./sunshine-display { };
  whisper-ctranslate2-cuda = pkgs.callPackage ./whisper-ctranslate2-cuda { };
}
