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
      source = "${piWeb.delegation}/lib/node_modules/pi-web-delegation";
      extensions = [ "dist/extension.js" ];
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
