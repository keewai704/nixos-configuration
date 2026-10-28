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
    edcb = final.callPackage ./edcb { upstream = inputs.edcb; };
    b25-decoder = final.callPackage ./b25-decoder { upstream = inputs.b25-decoder; };
    tsreplace = final.callPackage ./tsreplace { upstream = inputs.tsreplace; };
    konomitv = final.callPackage ./konomitv {
      upstream = inputs.konomitv;
      thirdparty = inputs.konomitv-thirdparty;
      inherit inputs;
    };
    torne-receiver = final.callPackage ./torne-receiver {
      upstream = inputs.torne-driver;
      bonDriverHeaders = inputs.edcb + "/BonCtrl";
    };
    mirakc-arib = final.callPackage ./mirakc-arib { upstream = inputs.mirakc-arib; };
    mirakc = final.callPackage ./mirakc {
      upstream = inputs.mirakc;
      swaggerUi = inputs.mirakc-swagger-ui;
    };
    bondriver-linuxmirakc = final.callPackage ./bondriver-linuxmirakc {
      upstream = inputs.bondriver-linuxmirakc;
    };
    helium = final.callPackage ./helium { };
    legcord = final.callPackage ./legcord { };
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
    uxplay = final.callPackage ./uxplay { };
    whisper-ctranslate2-cuda = final.callPackage ./whisper-ctranslate2-cuda { };
  };
}
