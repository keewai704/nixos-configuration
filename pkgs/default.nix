{ inputs }:
final: _previous:
let
  claude-code = inputs.claude-code.packages.${final.stdenv.hostPlatform.system}.default;
in
{
  local = {
    helium = final.callPackage ./helium { };
    livesync-bridge = final.callPackage ./livesync-bridge { };
    meltype = final.callPackage ./meltype {
      release = inputs.meltype-release;
      tags = inputs.meltype-tags;
    };
    millennium = final.callPackage ./millennium { upstream = inputs.millennium; };
    penpot-mcp = final.callPackage ./penpot-mcp { };
    proton-wineland = final.callPackage ./proton-wineland {
      release = inputs.proton-wineland-release;
    };
    sunshine-display = final.callPackage ./sunshine-display {
      umbriel = inputs.umbriel.packages.${final.stdenv.hostPlatform.system}.default;
    };
    t3code = final.callPackage ./t3code {
      releases = inputs.t3code-releases;
      inherit claude-code;
    };
    whisper-ctranslate2-cuda = final.callPackage ./whisper-ctranslate2-cuda { };
  };
}
