{ inputs, ... }:
{
  imports = [ inputs.hypr-island.nixosModules.default ];
  programs.dynamic-island.enable = true;
}
