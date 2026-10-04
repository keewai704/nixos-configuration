{ inputs, ... }:
{
  imports = [ inputs.hypr-brightness.nixosModules.default ];

  services.hypr-brightness.enable = true;
}
