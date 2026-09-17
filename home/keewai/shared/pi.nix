{
  config,
  lib,
  pkgs,
  ...
}:
let
  runtimePackages = [
    pkgs.nodejs
    pkgs.python3
    pkgs.jq
  ];
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
    extraPackages = runtimePackages;
    settings = {
      defaultProvider = "openai-codex";
      defaultModel = "gpt-6-astra";
      defaultThinkingLevel = "xhigh";
      defaultProjectTrust = "always";
      defaultTools = [
        "read"
        "bash"
        "edit"
        "write"
        "grep"
        "find"
        "ls"
      ];
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
        {
          source = "npm:pi-web-search@1.6.0";
          extensions = [ "src/index.ts" ];
          skills = [ ];
          prompts = [ ];
          themes = [ ];
        }
        {
          source = "npm:@narumitw/pi-lsp@0.49.7";
          extensions = [ "dist/index.ts" ];
          skills = [ ];
          prompts = [ ];
          themes = [ ];
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

  home.file = {
    ".pi/agent/APPEND_SYSTEM.md".source = ./pi/APPEND_SYSTEM.md;
    ".pi/agent/extensions/astra-cache.ts".source = ./pi/astra-cache.ts;
    ".pi/agent/extensions/cache-audit.ts".source = ./pi/cache-audit.ts;
    ".pi/agent/prompts/review.md".source = ./pi/review.md;
    ".pi/agent/pi-lsp.json".text = builtins.toJSON {
      timeout = 20000;
      servers = {
        nixd = {
          command = [ (lib.getExe pkgs.nixd) ];
          extensions = [ ".nix" ];
        };
        typescript = {
          command = [
            (lib.getExe pkgs.typescript-language-server)
            "--stdio"
          ];
          extensions = [
            ".ts"
            ".tsx"
            ".mts"
            ".cts"
            ".js"
            ".jsx"
            ".mjs"
            ".cjs"
          ];
        };
        lua = {
          command = [ (lib.getExe pkgs.lua-language-server) ];
          extensions = [ ".lua" ];
          pushDiagnosticsGraceMs = 3000;
        };
        bash = {
          command = [
            (lib.getExe pkgs.bash-language-server)
            "start"
          ];
          extensions = [
            ".sh"
            ".bash"
          ];
          initialization.bashIde.shellcheckPath = lib.getExe pkgs.shellcheck;
        };
      };
    };
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
