{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  helpers = pkgs.callPackage ../../../../pkgs/pi-codex-conversion-helpers { };
  shell = pkgs.writeShellScript "pi-codex-bash" ''
    export PATH=${lib.escapeShellArg osConfig.security.wrapperDir}:"$PATH"
    exec ${lib.getExe pkgs.bash} -o pipefail "$@"
  '';
in
{
  programs.pi-coding-agent.settings.shellPath = "${shell}";

  home.file.".pi/agent/pi-codex-conversion.json".source =
    (pkgs.formats.json { }).generate "pi-codex-conversion.json"
      {
        executionMode = "normal";
        scope.allProviders = "off";
        prompt.heavySystemPromptOverwrite = false;
        tools = {
          customRustBinariesDir = "${helpers}/bin";
          applyPatchOnly = false;
          viewImageOnly = false;
          viewImageFallback = false;
          autoReasoning = false;
        };
        compaction = {
          contextManagement = "remote";
          hybridCompaction = true;
          responsesCompaction = false;
          portableSummary = false;
        };
        openai = {
          fast = false;
          forceCachedWebSockets = false;
          proxyResponsesLite = false;
          cacheKeepalive = false;
          lunaCacheKeepaliveMinutes = 0;
          cacheDiagnostics = "off";
        };
        ui.backgroundShellWidget = true;
      };
}
