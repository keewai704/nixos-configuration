{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.cpak.nixosModules.default ];

  services.cpak = {
    enable = true;
    package = inputs.cpak.packages.${pkgs.stdenv.hostPlatform.system}.cpak.overrideAttrs (previous: {
      version = "2.14.6";
      __intentionallyOverridingVersion = true;
      ldflags = map (lib.replaceStrings
        [ "main.version=v${previous.version}" ]
        [ "main.version=v2.14.6" ]
      ) previous.ldflags;
    });
  };
}
