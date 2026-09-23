{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  adapter = pkgs.callPackage ../../../../pkgs/pi-mcp-adapter { };
  mcpServers = lib.mapAttrs (
    _: server:
    lib.filterAttrs (_: value: value != null) (
      builtins.intersectAttrs {
        command = null;
        args = null;
        env = null;
        url = null;
        headers = null;
      } server
    )
    // {
      lifecycle = "lazy";
    }
  ) config.programs.mcp.servers;
in
{
  imports = [ inputs.mcp-servers-nix.homeManagerModules.default ];
  programs.mcp.enable = true;
  programs.pi-coding-agent.settings.packages = lib.mkOrder 1100 [
    {
      source = "${adapter}/lib/node_modules/pi-mcp-adapter";
    }
  ];

  home.file.".pi/agent/mcp.json".text = builtins.toJSON {
    inherit mcpServers;
    settings = {
      hostConfigDiscovery = "off";
      directTools = false;
      scriptMode = true;
      mcpFooterStatus = "compact";
      notifyOnStartupConnect = false;
    };
  };

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
