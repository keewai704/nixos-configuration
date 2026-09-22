{ config, lib, ... }:
let
  webAccess = "${config.home.homeDirectory}/.pi/agent/npm/node_modules/pi-web-access/dist/index.js";
in
{
  programs.pi-coding-agent.settings = {
    packages = lib.mkOrder 1500 [
      {
        source = "npm:pi-subagents@0.70.0";
        extensions = [ "index.js" ];
      }
    ];
    subagents = {
      disableBuiltins = false;
      defaultExtensions = [ ];
      agentOverrides = {
        researcher.subagentOnlyExtensions = [ webAccess ];
        evidence-auditor.subagentOnlyExtensions = [ webAccess ];
      };
    };
  };

  home.file = {
    ".pi/agent/extensions/subagent/config.json".text = builtins.toJSON {
      asyncByDefault = true;
      defaultSubagentContext = "fresh";
      maxActiveAsyncRunsPerSession = 4;
      globalConcurrencyLimit = 4;
      maxSubagentDepth = 1;
      scheduledRuns.enabled = false;
    };
  };
}
