{
  inputs,
  pkgs,
  ...
}:
{
  home.packages = [
    (pkgs.callPackage ../../../pkgs/apple-music-client {
      src = inputs.apple-music-client;
      authService = inputs.apple-music-client.packages.${pkgs.stdenv.hostPlatform.system}.auth-service;
    })
    inputs.apple-music-client.packages.${pkgs.stdenv.hostPlatform.system}.auth-service
  ];
}
