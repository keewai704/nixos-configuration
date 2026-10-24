{ inputs, ... }:
{
  imports = [ inputs.cpak.nixosModules.default ];

  services.cpak.enable = true;
}
