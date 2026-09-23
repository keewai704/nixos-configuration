{ lib, pkgs, ... }:
let
  superpowers = pkgs.fetchFromGitHub {
    owner = "obra";
    repo = "superpowers";
    rev = "5bf4e78011075bcfc0dc295f0724994cd123ee71";
    hash = "sha256-rgeJhjQyABYlhlyFRmgyhbZmmmIPPNkch4CXyTkGEyM=";
    name = "superpowers-6.4.1";
  };
in
{
  programs.pi-coding-agent.settings.packages = lib.mkOrder 1600 [ "${superpowers}" ];
}
