{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  home.packages = [
    pkgs.brightnessctl
    pkgs.ddcutil
    pkgs.grimblast
    pkgs.moonlight-qt
    pkgs.pavucontrol
    (pkgs.callPackage ../../../pkgs/t3code {
      release = inputs.t3code-release;
      claude-code = inputs.claude-code.packages.${system}.default;
      codex = inputs.codex-cli.packages.${system}.default;
    })
  ];
}
