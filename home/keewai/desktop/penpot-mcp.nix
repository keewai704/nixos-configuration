{ lib, pkgs, ... }:

let
  penpotMcp = pkgs.callPackage ../../../pkgs/penpot-mcp { };
  penpotProxy = pkgs.writeShellApplication {
    name = "penpot-mcp";
    runtimeInputs = [ pkgs.mcp-proxy ];
    text = ''
      exec mcp-proxy --transport streamablehttp http://localhost:4401/mcp
    '';
  };
in
{
  codingAgents.mcpServers.penpot.command = lib.getExe penpotProxy;

  systemd.user.services = {
    penpot-mcp = {
      Unit.Description = "Local Penpot MCP server";
      Service = {
        ExecStart = lib.getExe penpotMcp;
        Environment = [
          "PENPOT_MCP_SERVER_PORT=4401"
          "PENPOT_MCP_WEBSOCKET_PORT=4402"
          "PENPOT_MCP_REMOTE_MODE=false"
          "PENPOT_MCP_DEVENV=false"
        ];
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    penpot-mcp-plugin = {
      Unit.Description = "Local Penpot MCP plugin assets";
      Service = {
        ExecStart = "${penpotMcp}/bin/penpot-mcp-plugin";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
