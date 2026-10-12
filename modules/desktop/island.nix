{ inputs, ... }:
{
  imports = [ inputs.island.nixosModules.default ];

  programs.island.enable = true;
}
