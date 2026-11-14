{ osConfig, pkgs, ... }:
let
  headers = pkgs.writers.writePython3 "tinyfish-mcp-headers" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./headers.py);
  headersHelper = pkgs.writeShellScript "tinyfish-mcp-headers-agenix" ''
    TINYFISH_API_KEY_FILE=${osConfig.age.secrets.tinyfish-api-key.path} exec ${headers}
  '';
in
{
  codingAgents.mcpServers.tinyfish = {
    url = "https://agent.tinyfish.ai/mcp";
    headersHelper = "${headersHelper}";
  };
}
