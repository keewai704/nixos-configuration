{ inputs, ... }:
{
  imports = [ inputs.hypr-brightness.homeManagerModules.default ];

  services.hypr-brightness.enable = true;
}
