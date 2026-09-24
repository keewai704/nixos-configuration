{
  config,
  lib,
  pkgs,
  ...
}:
let
  bridge = pkgs.callPackage ../../../../pkgs/pi-claude-bridge { };
in
{
  programs.pi-coding-agent.settings.packages = lib.mkOrder 1000 [
    {
      source = "${bridge}/lib/node_modules/pi-claude-bridge";
      extensions = [ "src/index.ts" ];
      skills = [ ];
      prompts = [ ];
      themes = [ ];
    }
  ];

  home.file.".pi/agent/claude-bridge.json".text = builtins.toJSON {
    askClaude.enabled = false;
    provider = {
      plan = "pro";
      longContextExtraUsage = false;
      strictMcpConfig = true;
      autoMemoryEnabled = false;
      pathToClaudeCodeExecutable = lib.getExe config.programs.claude-code.finalPackage;
    };
  };
}
