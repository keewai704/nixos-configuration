{ inputs, pkgs, ... }:
{
  home.packages = [
    (inputs.iphone-control.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
      browser = pkgs.local.helium;
    })
  ];
}
