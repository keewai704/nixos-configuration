{ pkgs }:
let
  browser-harness = pkgs.callPackage ./browser-harness { };
in
{
  inherit browser-harness;
  cua-driver = pkgs.callPackage ./cua-driver { };
  jev-ultrafast = pkgs.callPackage ./jev-ultrafast { inherit browser-harness; };
}
