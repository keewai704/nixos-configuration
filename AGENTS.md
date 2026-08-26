# Repository workflow

For every change that can affect the NixOS configuration on `orange`:

1. Run the formatting, static-analysis, evaluation, and build checks appropriate to the change.
2. Run `sudo nixos-rebuild test --flake .#orange`.
3. Verify networking and every affected service on the live system.
4. Only when those checks pass, run `sudo nixos-rebuild switch --flake .#orange` and verify the services again.

Do not run `switch` after a failed test or health check. Always report whether the change was applied to the running system and persisted as the boot default.

## Publishing web services on `orange`

For every HTTP, HTTPS, or WebSocket service that should be reachable by a user,
use this topology whenever the application supports it:

`tailnet client -> Tailscale Serve HTTPS -> loopback nginx -> loopback application`

1. Bind the application backend to `127.0.0.1` or a Unix socket. Do not bind it
   to the LAN or all interfaces.
2. Add the service to the existing nginx virtual host for
   `orange.tail1e65cd.ts.net`, normally under a dedicated path, and reuse the
   existing Tailscale Serve mapping from HTTPS port 443 to nginx at
   `127.0.0.1:8000`.
3. Do not point Tailscale Serve directly at an application backend or open the
   backend port in the global firewall or on `tailscale0` unless nginx genuinely
   cannot proxy the application's protocol or URL behavior.
4. Configure the application's external/base URL for its canonical tailnet
   HTTPS URL when supported. Preserve the forwarded host, scheme, and client IP;
   enable nginx WebSocket proxying when required.
5. If the preferred topology is not viable, use the least-exposed alternative
   and document the technical reason for the exception in the configuration.
6. Verify the canonical tailnet URL, redirects, static assets, and WebSockets as
   applicable. Also verify with `ss` that the backend is loopback-only and check
   `tailscale serve status` before considering the service healthy.

Declarative web-service changes remain subject to the test, live health-check,
and switch workflow above.
