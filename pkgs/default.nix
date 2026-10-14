{ inputs, pkgs }:
{
  helium = pkgs.callPackage ./helium { };
  pi = pkgs.callPackage ./pi { };
  t3code = pkgs.callPackage ./t3code {
    releases = inputs.t3code-releases;
    claude-code = inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
  sunshine-display = pkgs.callPackage ./sunshine-display { };
  whisper-ctranslate2-cuda = pkgs.callPackage ./whisper-ctranslate2-cuda { };
}
