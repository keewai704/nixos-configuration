{ inputs, pkgs, ... }:
let
  upstreamPackages = inputs.apple-music-client.packages.${pkgs.stdenv.hostPlatform.system};
  musicClient = pkgs.callPackage ../../../pkgs/apple-music-client {
    src = inputs.apple-music-client;
    authService = upstreamPackages.auth-service;
  };
in
{
  home.packages = [
    musicClient
    upstreamPackages.auth-service
  ];
}
