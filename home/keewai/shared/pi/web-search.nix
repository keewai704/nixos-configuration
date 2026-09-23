{ lib, pkgs, ... }:
let
  webAccess = pkgs.callPackage ../../../../pkgs/pi-web-access { };
  webSearchConfig = (pkgs.formats.json { }).generate "pi-web-search.json" {
    searchRouting = {
      providers = [ "openai" ];
      useCurrentModel = true;
      fallbackOn = [ "transient" ];
    };
    workflow = "none";
    allowBrowserCookies = false;
    fetchRouting.allowRemoteHostedProviders = false;
    pdf.provider = "unpdf";
  };
in
{
  programs.pi-coding-agent.settings.packages = lib.mkOrder 1200 [
    {
      source = "${webAccess}/lib/node_modules/pi-web-access";
      extensions = [ "dist/index.js" ];
      skills = [ ];
      prompts = [ ];
      themes = [ ];
    }
  ];

  xdg.configFile."pi/web-search.json".source = webSearchConfig;
  home.file.".pi/agent/web-search.json".source = webSearchConfig;
}
