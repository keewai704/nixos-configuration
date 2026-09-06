# Runtime host boundary

Before starting any task, and before reading or changing repository files,
running checks, rebuilding, deploying, or inspecting live services, determine
the host of the current local execution environment with `hostnamectl --static`
(fall back to `hostname`) and confirm it against `/etc/hostname`. If those
values disagree, stop and report the mismatch before making changes.

Treat the confirmed local runtime host as the only live system in scope. Do not
infer the live host from the repository path, a flake target mentioned in these
instructions, earlier conversation context, or the host whose declarative
configuration is being edited.

Do not use SSH, mosh, a remote shell, or any other remote-execution mechanism to
enter another host's workspace, inspect or change its checkout, run checks or
rebuilds there, deploy to it, or perform live health checks there. A remote
operation is allowed only when the user explicitly requests that specific
remote host and operation in the current request. General repository workflow
instructions never authorize remote access.

It is acceptable to edit another host's declarative configuration in the
current local checkout when the task requires it. In that case, restrict work
for that other host to local formatting, evaluation, and builds; do not contact
the host or apply the result there.

# Repository workflow

For every task that changes this repository, complete the applicable part of
this workflow before ending the work or reporting it as complete:

1. Record the locally confirmed runtime hostname and verify that the flake has a
   matching `nixosConfigurations.<runtime-host>` output. If it does not, stop
   instead of substituting another host.
2. Run the formatting, static-analysis, evaluation, and build checks appropriate
   to the change. Configuration-only checks for another host may be run locally,
   but do not treat that host as the live system.
3. Commit every intended change for the task. Do not include unrelated user
   changes, and confirm that no task-related change remains uncommitted.
4. Determine whether the committed change affects the confirmed runtime host's
   evaluated NixOS configuration, deployed files, or services. If it does, run
   `sudo nixos-rebuild test --flake .#<runtime-host>` locally against the
   committed state. Never use a different host's flake output for this live
   test.
5. When step 4 applies, verify networking and every affected service on the
   local live system.
6. When step 4 applies, only after the test and health checks pass, run
   `sudo nixos-rebuild switch --flake .#<runtime-host>` locally.
7. When step 4 applies, verify networking and every affected service again
   after `switch`, and confirm that the running system and boot-default system
   match the tested committed configuration.

Formatting, appropriate checks, and a clean task commit are always mandatory.
The live `test`, health-check, `switch`, and post-switch gates are mandatory
only when the change affects the confirmed runtime host. Documentation-only
changes, repository tooling that is not deployed, and configuration used only
by another host stop after their appropriate checks and commit; build another
host locally when applicable, but do not activate an unrelated generation on
the runtime host. Report that the live gates were not applicable. If an
applicable test or health check fails, do not run `switch` or report the task as
complete; fix the problem and repeat the workflow, or report the work as
blocked. Always report whether the change was committed and, when applicable,
whether it was applied to the running system and persisted as the boot default.

## Package sources owned by `keewai704`

For packages sourced from GitHub repositories owned by `keewai704`, explicitly
select the `main` branch (for Git flake inputs, use `?ref=main`). Keep revisions
and hashes pinned for reproducibility; refresh them from `main` when updating
the package. Do not rely on the repository's default branch.

## Publishing web services on `orange`

For every HTTP, HTTPS, or WebSocket service that should be reachable by a user,
use this topology:

`tailnet client -> Tailscale Serve HTTPS -> loopback nginx -> loopback application`

1. Port 443 is the only permitted user-facing web ingress. Do not expose HTTP,
   HTTPS, WebSocket, TLS-terminated TCP, or an application backend on any other
   external port. Loopback-only ports are permitted solely as internal proxy
   hops.
2. Bind the application backend to `127.0.0.1` or a Unix socket. Do not bind it
   to the LAN or all interfaces.
3. Add the service to the existing nginx virtual host for
   `orange.tail1e65cd.ts.net`, normally under a dedicated path, and reuse the
   existing Tailscale Serve mapping from HTTPS port 443 to nginx at
   `127.0.0.1:8000`.
4. Do not point Tailscale Serve directly at an application backend or open the
   backend port in the global firewall or on `tailscale0`.
5. Configure the application's external/base URL for its canonical tailnet
   HTTPS URL when supported. Preserve the forwarded host, scheme, and client IP;
   enable nginx WebSocket proxying when required.
6. If an application does not support a subpath, patch it, rebuild its client,
   or add a safe adapter. Never work around the limitation with another
   externally reachable port. If no safe port-443 solution is viable, stop and
   report the service as blocked instead of publishing it.
7. Verify the canonical tailnet URL, redirects, static assets, and WebSockets as
   applicable. Also verify with `ss` that the backend is loopback-only and that
   `tailscale serve status` contains exactly one web listener: HTTPS port 443.

Declarative web-service changes remain subject to the test, live health-check,
and switch workflow above only when the confirmed runtime host is `orange`. On
any other runtime host, validate the Orange configuration locally and do not
SSH to Orange or deploy it remotely.
