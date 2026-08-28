{
  orangeSettings,
  pkgs,
  ...
}:

let
  inherit (orangeSettings) camofoxAgentUserId camofoxApiPort;
  camofoxUrl = "http://127.0.0.1:${toString camofoxApiPort}";
  camofoxPackage = pkgs.callPackage ./camofox-package.nix {
    websockify = pkgs.python3Packages.websockify;
  };
in
{
  home-manager.users.keewai = {
    home.sessionVariables.CAMOFOX_URL = camofoxUrl;

    systemd.user.sessionVariables.CAMOFOX_URL = camofoxUrl;

    mcp-servers.settings.servers.camofox-browser = {
      command = "${camofoxPackage}/bin/camofox-browser-mcp";
      env = {
        CAMOFOX_BASE_URL = camofoxUrl;
        CAMOFOX_USER_ID = camofoxAgentUserId;
        CAMOFOX_SESSION_KEY = "default";
      };
    };
  };
}
