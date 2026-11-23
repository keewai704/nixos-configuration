{ pkgs, ... }:
{
  home-manager.users.keewai.home.packages = [
    (pkgs.ladybird.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./nixos-sandbox.patch ];
    }))
  ];
}
