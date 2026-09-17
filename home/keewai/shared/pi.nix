{
  config,
  lib,
  pkgs,
  ...
}:
let
  mcpServerNames = [
    "context7"
    "nixos"
    "openaiDeveloperDocs"
  ];
  mcpServers = lib.mapAttrs (
    name: server:
    if lib.elem name mcpServerNames then
      lib.filterAttrs (_: value: value != null) (
        builtins.intersectAttrs {
          command = null;
          args = null;
          env = null;
          url = null;
          headers = null;
        } server
      )
      // {
        lifecycle = "lazy";
      }
    else
      { disabled = true; }
  ) config.programs.mcp.servers;
in
{
  programs.pi-coding-agent = {
    enable = true;
    package = pkgs.callPackage ../../../pkgs/pi-coding-agent { };
    extraPackages = [ pkgs.nodejs ];
    settings = {
      defaultProvider = "openai-codex";
      defaultModel = "gpt-6-astra";
      defaultThinkingLevel = "xhigh";
      enabledModels = [ "openai-codex/gpt-6-astra" ];
      showCacheMissNotices = true;
      enableInstallTelemetry = false;
      enableAnalytics = false;
      npmCommand = [
        "npm"
        "--ignore-scripts"
        "--no-audit"
        "--no-fund"
      ];
      packages = [
        {
          source = "npm:pi-mcp-adapter@2.34.0";
          skills = [ ];
        }
      ];
      skills = [ "/etc/codex/skills/ponytail" ];
      compaction = {
        enabled = true;
        reserveTokens = 131072;
        keepRecentTokens = 32768;
      };
    };
    models.providers.openai-codex.modelOverrides.gpt-6-astra.contextWindow = 872000;
  };

  home.packages = [
    (pkgs.writeShellApplication {
      name = "pi-astra";
      runtimeInputs = [ pkgs.nodejs ];
      text = ''
        exec ${lib.getExe config.programs.pi-coding-agent.package} --tools read,bash,edit,write,mcp "$@"
      '';
    })
  ];

  home.file = {
    ".pi/agent/APPEND_SYSTEM.md".source = ./pi/APPEND_SYSTEM.md;
    ".pi/agent/extensions/astra-cache.ts".source = ./pi/astra-cache.ts;
    ".pi/agent/extensions/cache-audit.ts".source = ./pi/cache-audit.ts;
    ".pi/agent/prompts/review.md".source = ./pi/review.md;
    ".pi/agent/mcp.json".text = builtins.toJSON {
      inherit mcpServers;
      settings = {
        hostConfigDiscovery = "off";
        directTools = false;
        scriptMode = false;
        mcpFooterStatus = "compact";
        notifyOnStartupConnect = false;
      };
    };
  };
}
