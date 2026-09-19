{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  subagentResources = pkgs.callPackage ../../../../pkgs/pi-subagents-resources { };
  codexConversionHelpers = pkgs.callPackage ../../../../pkgs/pi-codex-conversion-helpers { };
in
{
  programs.pi-coding-agent = {
    enable = true;
    package = pkgs.callPackage ../../../../pkgs/pi-coding-agent { };
    extraPackages = [
      pkgs.nodejs
      pkgs.python3
      pkgs.jq
    ];
    settings = {
      defaultProvider = "openai-codex";
      defaultModel = "gpt-6-astra";
      defaultThinkingLevel = "xhigh";
      defaultProjectTrust = "always";
      shellCommandPrefix = ''
        export PATH=${lib.escapeShellArg osConfig.security.wrapperDir}:"$PATH"
        set -o pipefail
      '';
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
          source = "npm:@howaboua/pi-codex-conversion@${codexConversionHelpers.version}";
          extensions = [ "dist/index.js" ];
          skills = [ ];
          prompts = [ ];
          themes = [ ];
        }
        {
          source = "npm:pi-mcp-adapter@2.34.0";
        }
        {
          source = "npm:pi-web-access@0.29.0";
          extensions = [ "index.ts" ];
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
        {
          source = "npm:pi-subagents@${subagentResources.version}";
          skills = [ ];
          prompts = [ "!prompts/council.md" ];
        }
      ];
      skills = [ "${subagentResources}/skills" ];
      prompts = [ "${subagentResources}/prompts/council.md" ];
      subagents = {
        defaultModel = "openai-codex/gpt-5.6-luna";
        agentOverrides = {
          codex-exec.disabled = true;
          codex-exec-writer.disabled = true;
          evidence-auditor.thinking = "max";
          oracle.thinking = "max";
          reviewer.thinking = "max";
          scout.thinking = "high";
          worker.thinking = "max";
        };
      };
      compaction = {
        enabled = true;
        reserveTokens = 131072;
        keepRecentTokens = 32768;
      };
    };
    models.providers.openai-codex.modelOverrides.gpt-6-astra.contextWindow = 872000;
  };

  home.file = {
    ".pi/agent/APPEND_SYSTEM.md".source = ./APPEND_SYSTEM.md;
    ".pi/agent/extensions/cache-audit.ts".source = ./extensions/cache-audit.ts;
    ".pi/agent/extensions/jev-analysis.ts".source = ./extensions/jev-analysis.ts;
    ".pi/agent/prompts/review.md".source = ./prompts/review.md;
  };
}
