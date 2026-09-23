{ lib, pkgs, ... }:
let
  piTasks = pkgs.callPackage ../../../../pkgs/pi-tasks { };
in
{
  programs.pi-coding-agent.settings.packages = lib.mkOrder 1600 [
    {
      source = "${piTasks}";
      extensions = [ "index.ts" ];
      skills = [ ];
      prompts = [ ];
      themes = [ ];
    }
  ];

  home.file.".pi/agent/tasks-config.json".text = builtins.toJSON {
    taskScope = "session-global";
    autoCascade = false;
    autoClearCompleted = "never";
    collapseCompleted = true;
    sortOrder = "active";
  };
}
