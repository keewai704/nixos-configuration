{ pkgs, ... }:
let
  helpers = pkgs.callPackage ../../../../pkgs/pi-codex-conversion-helpers { };
in
{
  home.file.".pi/agent/pi-codex-conversion.json".source =
    (pkgs.formats.json { }).generate "pi-codex-conversion.json"
      {
        executionMode = "normal";
        scope.allProviders = "extras";
        prompt.heavySystemPromptOverwrite = false;
        tools = {
          customRustBinariesDir = "${helpers}/bin";
          applyPatchOnly = true;
          viewImageOnly = true;
          viewImageFallback = false;
          autoReasoning = false;
        };
        compaction = {
          contextManagement = "off";
          hybridCompaction = false;
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
        ui.backgroundShellWidget = false;
      };
}
