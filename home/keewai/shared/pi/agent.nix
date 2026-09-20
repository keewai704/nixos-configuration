{
  lib,
  osConfig,
  pkgs,
  ...
}:
{
  programs.pi-coding-agent = {
    enable = true;
    package = pkgs.callPackage ../../../../pkgs/pi-coding-agent { };
    extraPackages = [
      pkgs.ast-grep
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
    ".pi/agent/extensions/notify.ts".source = ./extensions/notify.ts;
    ".pi/agent/prompts/review.md".source = ./prompts/review.md;
  };
}
