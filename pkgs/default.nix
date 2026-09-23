{ pkgs }:
{
  cua-driver = pkgs.callPackage ./cua-driver { };
  wine4office = pkgs.callPackage ./wine4office { };
}
