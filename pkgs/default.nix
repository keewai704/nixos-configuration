{ inputs }:
final: previous:
let
  claude-code = inputs.claude-code.packages.${final.stdenv.hostPlatform.system}.default;
in
{
  mcp-proxy = previous.mcp-proxy.override {
    python3Packages = final.python3Packages // {
      mcp = final.python3Packages.mcp_1;
    };
  };

  local = {
    helium = final.callPackage ./helium { };
    livesync-bridge = final.callPackage ./livesync-bridge { };
    meltype = final.callPackage ./meltype {
      release = inputs.meltype-release;
      tags = inputs.meltype-tags;
    };
    millennium = final.callPackage ./millennium { upstream = inputs.millennium; };
    owly = final.callPackage ./owly { upstream = inputs.owly; };
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
