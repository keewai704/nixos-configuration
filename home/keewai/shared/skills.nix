{ lib, ... }:
let
  skillRoot = ../../../skills;

  skillEntries =
    lib.mapAttrs'
      (
        name: _type:
        lib.nameValuePair ".agents/skills/${name}" {
          source = skillRoot + "/${name}";
          force = true;
        }
      )
      (
        lib.removeAttrs (builtins.readDir skillRoot) [
          "ponytail"
          "luna-delegation"
        ]
      );

in
{
  home.file = skillEntries;
}
