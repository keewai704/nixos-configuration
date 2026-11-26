{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  host = "127.0.0.1";
  port = 8040;

  models = {
    "kimi-k3.1-pro" = "Kimi K3.1 Pro";
    "glm-5.3" = "GLM-5.3";
    "glm-5.3-flash" = "GLM-5.3 Flash";
    "deepseek-v4-pro" = "DeepSeek V4 Pro";
    "deepseek-v4.1-flash" = "DeepSeek V4.1 Flash";
    "gpt-6-luna" = "GPT-6 Luna";
    "gemini-4-argon" = "Gemini 4 Argon";
    "mimo-v2.6-flash" = "MiMo-V2.6 Flash";
    "qwen3.8-flash" = "Qwen3.8 Flash";
  };

  router = pkgs.writers.writePython3 "opencode-go-router" {
    libraries = [ pkgs.python3Packages.aiohttp ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./router.py);
in
{
  programs.claude-code.settings = {
    env.ANTHROPIC_BASE_URL = "http://${host}:${toString port}";
    modelPicker.options = lib.mapAttrsToList (id: label: {
      model = "opencode-go/${id}";
      inherit label;
      description = "OpenCode Go";
    }) models;
  };

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
