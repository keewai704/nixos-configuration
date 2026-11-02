{ pkgs, ... }:
let
  headersHelper = pkgs.writers.writePython3 "tinyfish-mcp-headers" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./headers.py);
in
{
  codingAgents.mcpServers.tinyfish = {
    url = "https://agent.tinyfish.ai/mcp";
    headersHelper = "${headersHelper}";
  };
}
