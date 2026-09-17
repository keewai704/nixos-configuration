{ pkgs }:
{
  chatgpt-desktop = pkgs.callPackage ./chatgpt-desktop { };
  cua-driver = pkgs.callPackage ./cua-driver { };
}
