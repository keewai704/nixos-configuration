{
  config,
  lib,
  pkgs,
  ...
}:
let
  secret = config.age.secrets.browser-control-mcp-secret.path;

  server = pkgs.writeShellScript "browser-control-mcp" ''
    EXTENSION_SECRET="$(< ${secret})"
    export EXTENSION_SECRET
    exec ${lib.getExe pkgs.local.browser-control-mcp} "$@"
  '';
in
{
  age.secrets.browser-control-mcp-secret = {
    file = ../../../../secrets/browser-control-mcp-secret.age;
    mode = "0400";
    owner = "keewai";
  };

  home-manager.users.keewai = {
    programs.zen-browser.policies.ExtensionSettings."{6ba257e0-fbce-4d50-8471-25de7f024c1e}" = {
      installation_mode = "force_installed";
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/browser-control-mcp/latest.xpi";
    };

    codingAgents.mcpServers.browser-control = {
      command = "${server}";
      env.EXTENSION_PORT = "8089";
    };
  };
}
