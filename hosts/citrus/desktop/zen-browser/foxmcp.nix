{ lib, pkgs, ... }:
{
  home-manager.users.keewai = {
    programs.zen-browser.policies.ExtensionSettings."foxmcp@codemud.org" = {
      installation_mode = "force_installed";
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/foxmcp/latest.xpi";
    };

    codingAgents.mcpServers.foxmcp = {
      command = lib.getExe pkgs.local.foxmcp;
      args = [
        "--stdio"
        "--single-instance"
      ];
    };
  };
}
