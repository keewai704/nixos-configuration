{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  host = "127.0.0.1";
  port = 8040;

  router = pkgs.writers.writePython3 "opencode-go-router" {
    libraries = [ pkgs.python3Packages.aiohttp ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./router.py);

  syncModels = pkgs.writers.writePython3 "opencode-go-sync-models" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./sync-models.py);
in
{
  programs.claude-code.settings.env.ANTHROPIC_BASE_URL = "http://${host}:${toString port}";

  home.activation.opencodeGoModels =
    lib.hm.dag.entryAfter [ "claudeCodeSettings" "codingAgentConfig" ]
      ''
        run ${syncModels} ${config.programs.claude-code.configDir}/settings.json \
          || warnEcho "Keeping the previous OpenCode Go models in Claude Code's model picker"
      '';

  systemd.user.services.opencode-go-router = {
    Unit.Description = "Route Claude Code requests for OpenCode Go models";
    Service = {
      ExecStart = "${router} ${host} ${toString port} ${osConfig.age.secrets.opencode-api-key.path}";
      Restart = "always";
      RestartSec = 1;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
