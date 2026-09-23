{
  config,
  lib,
  pkgs,
  ...
}:
let
  piWeb = import ./web-package.nix { inherit config pkgs; };
in
{
  programs.pi-coding-agent.settings.packages = lib.mkOrder 1500 [
    {
      source = "${piWeb}/lib/node_modules/@agegr/pi-web";
      extensions = [ "pi-web-native-subagents/subagent-cli-extension.js" ];
      skills = [ ];
      prompts = [ ];
      themes = [ ];
    }
  ];
  home.file.".pi/agent/agents".source = pkgs.writeTextDir "settings.json" (
    builtins.toJSON {
      version = 1;
      builtInEnabled = true;
      maxConcurrent = 4;
    }
  );
}
