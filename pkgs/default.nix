{ inputs, pkgs }:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  apple-music-client = pkgs.callPackage ./apple-music-client {
    src = inputs.apple-music-client;
    authService = inputs.apple-music-client.packages.${system}.auth-service;
  };
  chatgpt-desktop = pkgs.callPackage ./chatgpt-desktop { };
  cua-driver = pkgs.callPackage ./cua-driver { };
  millennium-steam = import ./millennium-steam {
    inherit (pkgs) lib stdenv;
    inherit (inputs) millennium;
  };
}
