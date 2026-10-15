{ inputs }:
final: _previous:
let
  claude-code = inputs.claude-code.packages.${final.stdenv.hostPlatform.system}.default;
in
{
  local = {
    claude-desktop = final.callPackage ./claude-desktop {
      releases = inputs.claude-desktop-release;
      inherit claude-code;
    };
    helium = final.callPackage ./helium { };
    hypruse = final.callPackage ./hypruse { };
    impasto = final.callPackage ./impasto { inherit (inputs) impasto; };
    livesync-bridge = final.callPackage ./livesync-bridge { };
    meltype = final.callPackage ./meltype {
      release = inputs.meltype-release;
      tags = inputs.meltype-tags;
    };
    penpot-mcp = final.callPackage ./penpot-mcp { };
    proton-wineland = final.callPackage ./proton-wineland {
      release = inputs.proton-wineland-release;
    };
    sunshine-display = final.callPackage ./sunshine-display { };
    t3code = final.callPackage ./t3code {
      releases = inputs.t3code-releases;
      inherit claude-code;
    };
    whisper-ctranslate2-cuda = final.callPackage ./whisper-ctranslate2-cuda { };
  };
}
