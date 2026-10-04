{ lib, ... }:
let
  skillRoot = ../../../skills;
  skillNames = builtins.attrNames (builtins.readDir skillRoot);

  linkSkills = lib.genAttrs' skillNames (
    name:
    lib.nameValuePair ".claude/skills/${name}" {
      source = skillRoot + "/${name}";
      force = true;
    }
  );
in
{
  home.file = linkSkills;
}
