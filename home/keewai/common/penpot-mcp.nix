{ lib, pkgs, ... }:

let
  penpotMcp = pkgs.writeShellApplication {
    name = "penpot-mcp";
    runtimeInputs = [ pkgs.mcp-proxy ];
    text = ''
      tokenFile="''${XDG_CONFIG_HOME:-$HOME/.config}/penpot/mcp-token"
      if [ ! -r "$tokenFile" ]; then
        echo "penpot-mcp: missing $tokenFile; generate an MCP key in Penpot settings" >&2
        exit 1
      fi
      token=$(tr -d '[:space:]' < "$tokenFile")
      exec mcp-proxy --transport streamablehttp "https://orange.tail1e65cd.ts.net/penpot/mcp/stream?userToken=$token"
    '';
  };
in
{
  codingAgents.mcpServers.penpot.command = lib.getExe penpotMcp;
}
