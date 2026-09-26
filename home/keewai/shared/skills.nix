{ lib, ... }:
let
  skillRoot = ../../../skills;
  skillNames = builtins.attrNames (builtins.readDir skillRoot);

  linkSkills =
    directory:
    lib.genAttrs' skillNames (
      name:
      lib.nameValuePair "${directory}/${name}" {
        source = skillRoot + "/${name}";
        force = true;
      }
    );
in
{
  home.file = linkSkills ".agents/skills" // linkSkills ".claude/skills";
}
