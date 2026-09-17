{ inputs, pkgs, ... }:
{
  imports = [ inputs.mcp-servers-nix.homeManagerModules.default ];
  programs.mcp.enable = true;

  mcp-servers = {
    programs = {
      context7.enable = true;

      nixos = {
        enable = true;
        env = {
          FASTMCP_CHECK_FOR_UPDATES = "off";
          FASTMCP_SHOW_SERVER_BANNER = "false";
        };
      };

      serena = {
        enable = true;
        context = "agent";
        enableWebDashboard = false;
        args = [ "--project-from-cwd" ];
        extraPackages = [
          pkgs.nixd
          pkgs.nixfmt
        ];
        env = {
          FASTMCP_ENV_FILE = "/dev/null";
          SERENA_USAGE_REPORTING = "false";
        };
      };
    };

    settings.servers = {
      openaiDeveloperDocs.url = "https://developers.openai.com/mcp";
    };
  };
}
