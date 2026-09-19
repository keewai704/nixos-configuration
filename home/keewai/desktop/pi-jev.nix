{ lib, pkgs, ... }:
let
  browser-harness = pkgs.callPackage ../../../pkgs/browser-harness { };
  jev-ultrafast = pkgs.callPackage ../../../pkgs/jev-ultrafast { inherit browser-harness; };
  python = pkgs.python3.withPackages (ps: [ (ps.toPythonModule jev-ultrafast) ]);
  runner = pkgs.writeShellApplication {
    name = "pi-jev-runner";
    runtimeInputs = [ pkgs.procps ];
    text = ''
      export BH_TELEMETRY=0 BH_UPDATE_CHECK=0
      exec ${lib.getExe python} -B ${./pi-jev/runner.py}
    '';
  };
in
{
  home.packages = [
    browser-harness
    jev-ultrafast
  ];
  home.file.".pi/agent/extensions/jev-browser.ts".source = pkgs.replaceVars ./pi-jev/extension.ts {
    runner = lib.getExe runner;
  };
}
