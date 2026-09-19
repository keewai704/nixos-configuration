{ pkgs, ... }:
let
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
  xdg.configFile."pi/web-search.json".source = webSearchConfig;
  home.file.".pi/agent/web-search.json".source = webSearchConfig;
}
