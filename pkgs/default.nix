{ pkgs }:
let
  browser-harness = pkgs.callPackage ./browser-harness { };
in
{
  inherit browser-harness;
  icloud-keychain = pkgs.callPackage ./icloud-keychain { };
  icloud-keychain-client = pkgs.callPackage ./icloud-keychain/client.nix { };
  cua-driver = pkgs.callPackage ./cua-driver { };
  jev-ultrafast = pkgs.callPackage ./jev-ultrafast { inherit browser-harness; };
}
