{ lib, ... }:
let
  inherit (import ../settings.nix) tailnetHostname tailnetOrigin t3codePort;
  mkProxyLocation = import ./web/proxy.nix;
  proxy = mkProxyLocation t3codePort "";
  mobileScopes = lib.concatStringsSep "+" (
    map (scope: builtins.replaceStrings [ ":" ] [ "%3A" ] scope) [
      "orchestration:read"
      "orchestration:operate"
      "settings:write"
      "providers:manage"
      "environment:maintain"
      "preview:operate"
      "diagnostics:read"
      "terminal:read"
      "terminal:operate"
      "filesystem:read"
      "filesystem:write"
      "source-control:write"
      "access:read"
      "access:write"
      "relay:read"
      "relay:write"
    ]
  );
  legacyMobileScopes = "orchestration(?:%3[Aa]|:)read(?:[+]|%20)orchestration(?:%3[Aa]|:)operate(?:[+]|%20)terminal(?:%3[Aa]|:)operate(?:(?:[+]|%20)review(?:%3[Aa]|:)write)?(?:[+]|%20)relay(?:%3[Aa]|:)read";
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
    "/ws"
  ];
in
{
  orange.healthMonitor = {
    userUnits = [ "t3code.service" ];
    loopbackPorts = [ t3codePort ];
  };

  home-manager.users.keewai.services.t3code = {
    enable = true;
    port = t3codePort;
  };

  services.nginx.virtualHosts.${tailnetHostname}.locations =
    lib.genAttrs (map (path: "^~ ${path}") apiPrefixes) (_: proxy)
    // lib.genAttrs (map (path: "= ${path}") apiEndpoints) (_: proxy)
    // {
      "= /oauth/token" = mkProxyLocation t3codePort ''
        client_max_body_size 16k;
        client_body_buffer_size 16k;
        client_body_in_single_buffer on;
        proxy_set_body $t3_mobile_token_body;
      '';
      "~ ^/api/assets/[A-Za-z0-9_-]+[.][A-Za-z0-9_-]+/" = proxy;
      "= /pair".return = "302 ${tailnetOrigin}/t3/pair$is_args$args";
      "= /t3".return = "308 ${tailnetOrigin}/t3/";
      "^~ /t3/" = (mkProxyLocation t3codePort "") // {
        proxyPass = "http://127.0.0.1:${toString t3codePort}/";
      };
    };

  services.nginx.appendHttpConfig = ''
    map "$http_user_agent|$http_dpop|$http_authorization|$request_method" $t3_legacy_mobile_token_request {
      default 0;
      "~^T3Code/110(?: [^|]*)?[|][|][|]POST$" 1;
    }
    map "$t3_legacy_mobile_token_request|$request_body" $t3_mobile_token_body {
      default $request_body;
      "~^1[|](?<t3_scope_prefix>(?:(?!scope=)[^&]+&)*)scope=${legacyMobileScopes}(?<t3_scope_suffix>(?:&(?!scope=)[^&]+)*)$" "''${t3_scope_prefix}scope=${mobileScopes}''${t3_scope_suffix}";
    }
  '';
}
