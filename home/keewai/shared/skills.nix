{ lib, ... }:
let
  skillRoot = ../../../skills;

  skillEntries = lib.mapAttrs' (
    name: _type:
    lib.nameValuePair ".agents/skills/${name}" {
      source = skillRoot + "/${name}";
      force = true;
    }
  ) (builtins.readDir skillRoot);

in
{
  home.file = skillEntries;
}
