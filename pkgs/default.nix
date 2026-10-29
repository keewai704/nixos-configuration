{ inputs }:
final: _:
let
  claude-code = inputs.claude-code.packages.${final.stdenv.hostPlatform.system}.default;
in
{
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
    t3code = final.callPackage ./t3code {
      releases = inputs.t3code-releases;
      inherit claude-code;
    };
  };
}
