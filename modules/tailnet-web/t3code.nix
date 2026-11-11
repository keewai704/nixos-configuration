settings:
{ lib, ... }:
let
  inherit (settings) tailnetHostname tailnetOrigin t3codePort;
  mkProxyLocation = import ./proxy.nix;
  proxy = mkProxyLocation t3codePort "";
  apiPrefixes = [
    "/.well-known/t3/"
    "/api/orchestration/"
    "/api/projects/"
    "/api/pull-requests/"
    "/api/connect/"
    "/api/t3-connect/"
    "/api/hooks/"
    "/api/attachments/upload/"
    "/api/preview-stream/"
    "/api/device-hub/"
    "/api/auth/websocket-ticket/"
    "/oauth/mcp/"
  ];
  apiEndpoints = [
    "/.well-known/oauth-protected-resource"
    "/.well-known/oauth-protected-resource/mcp"
    "/.well-known/oauth-authorization-server"
    "/api/auth/session"
    "/api/auth/browser-session"
    "/api/auth/websocket-ticket"
    "/api/auth/pairing-token"
    "/api/auth/pairing-links"
    "/api/auth/pairing-links/revoke"
    "/api/auth/clients"
    "/api/auth/clients/revoke"
    "/api/auth/clients/revoke-others"
    "/api/projects"
    "/api/observability/v1/traces"
    "/mcp"
    "/oauth/token"
    "/ws"
  ];
in
{
  home-manager.users.keewai.services.t3code = {
    enable = true;
    port = t3codePort;
    webOrigin = tailnetOrigin;
  };

  services.nginx.virtualHosts.${tailnetHostname}.locations =
    lib.genAttrs (map (path: "^~ ${path}") apiPrefixes) (_: proxy)
    // lib.genAttrs (map (path: "= ${path}") apiEndpoints) (_: proxy)
    // {
      "~ ^/api/assets/[A-Za-z0-9_-]+[.][A-Za-z0-9_-]+/" = proxy;
      "= /pair".return = "302 ${tailnetOrigin}/t3/pair$is_args$args";
      "= /connect-agent".return = "302 ${tailnetOrigin}/t3/connect-agent$is_args$args";
      "= /t3".return = "308 ${tailnetOrigin}/t3/";
      "^~ /t3/" = proxy // {
        proxyPass = "http://127.0.0.1:${toString t3codePort}/";
      };
    };
}
