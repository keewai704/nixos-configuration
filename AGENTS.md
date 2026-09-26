# Repository working agreement

Deliver the requested change through the checks, commit, and local deployment
that apply below. Routine local work needs no repeated approval. Ask when a
missing decision changes the outcome, scope, or authority; while blocked, finish
independent authorized work and identify what remains. Audits and advice are
read-only unless changes are requested.

## Find the right source

Use [README.md](README.md) to locate architecture or editing entry points when
needed, not as a mandatory pre-read. Read the affected implementation and callers;
reuse context that has not changed.

| Responsibility | Source |
| --- | --- |
| Claude Code and Codex packages and defaults | `home/keewai/shared/coding-agents.nix` |
| Distributed personal skills | `skills/` |
| Repository-only validation guidance | `.agents/skills/nixos-validation/` |

Edit these sources, not generated links under `~/.claude/skills` or `~/.agents/skills`.
Persistent agent instructions, prompts, and skills are English; respond in the
user's language. Keep policy/navigation in AGENTS.md and README.md, and validation
procedures in the validation skill. Do not add repository-local `docs/`, `checks/`,
standalone check suites, or documentation files elsewhere. Skill references,
upstream documentation, disposable validation, package-local tests, and upstream
build tests are allowed. Do not add code comments; preserve shebangs and completion
directives.

## Authority and host identity

A change request authorizes necessary local edits, disposable checks, repairs
caused by the change, commits, and the local activation below. Unrelated work,
remote operations, push/publication, private-data uploads, and destructive actions
need authorization for the specific operation. SSH, mosh, and remote shells need
explicit authorization for the host and operation.

Before live-state inspection or host-dependent work, confirm that
`hostnamectl --static` matches `/etc/hostname` (`hostname` is the fallback).
Reuse that result until identity becomes uncertain. A mismatch blocks
host-dependent work, not read-only source analysis. Paths and flake targets do not
identify the running host. Require `nixosConfigurations.<runtime-host>`; never
activate another host's output locally. Another host's sources may be edited,
evaluated, or built locally without connecting to it.

## Placement and system integration

Match filenames to responsibilities. Keep tightly coupled code together; use a
named module for a substantial feature rather than placing it in a convenient
import. `hosts/<host>/default.nix` is for imports and small host-wide settings;
`modules/common.nix` is only for settings used by every host. Scope moves and
caller updates to the request, and explain non-obvious placement choices.

Personal applications, CLI tools, shell settings, user services, and files belong
in `home/<user>/common.nix`, `shared/`, or `desktop/`. Prefer suitable
`programs.*`/`services.*` modules, then `home.packages`. Every host loads the common
profile; `modules/desktop.nix` adds the shared desktop profile, with hardware
differences expressed by capability. `modules/home-manager.nix` owns the NixOS
connection. `useUserPackages = true` puts packages in
`/etc/profiles/per-user/<user>`; deployment still uses NixOS activation.

For ownership changes, inspect pinned modules and upstream requirements. Keep
required boot/login, daemon, kernel/driver, udev, PAM, polkit, D-Bus,
capability/setuid, graphics, and system-font integration at system scope. Do not
disable integration modules or empty package lists merely to move executables
unless that integration is explicitly replaced. Clients and daemons may have
different owners; build-only and service-internal dependencies stay with their
consumer. Check affected profiles, plugins, native messaging, MIME handlers,
autostart, sessions, and device access. Explain why each remaining system-side
application needs that integration. Moving a package does not sandbox it or
reduce its privileges.

## Completion gates

1. Inspect Git status, staged and unstaged changes before editing; record the
   starting commit. Preserve unrelated changes: do not format, stage, stash,
   reset, or delete them. Use an isolated worktree when an occupied index or
   unrelated changes could affect evaluation/activation; report a blocker if
   isolation is unavailable.
2. Use [nixos-validation](.agents/skills/nixos-validation/SKILL.md) to select checks
   for the changed behavior. Format only task files. Stage new files before
   Git-flake checks, inspect the task-only staged diff, and use
   `--no-write-lock-file` unless updating inputs was requested. Reuse passing
   evidence with unchanged inputs; broaden checks for failures or unresolved
   concerns, not for a fixed number of passes. Complete any review required by
   the active instructions or user before committing.
3. Commit all intended changes without unrelated work and confirm no task changes
   remain uncommitted.
4. If the commit affects the runtime host's evaluated configuration, deployed
   files, or services, record its expected system store path and relevant runtime
   baseline. Run `sudo nixos-rebuild test --flake .#<runtime-host>` on that
   committed state, using its evaluation/build rather than prebuilding the same
   output. Coding-agent settings and distributed `skills/` affect every host.
5. After `test`, check network connectivity, failed system/user units, and every
   affected service's behavior. New failures or regressions block `switch`.
6. Only after those gates pass, run
   `sudo nixos-rebuild switch --flake .#<runtime-host>`. Repeat the network,
   failed-unit, and affected-service checks. Confirm `/run/current-system` and
   `/nix/var/nix/profiles/system` both match the tested store path.

These activation and post-activation gates are distinct; earlier passing checks
do not replace them. If a gate fails, repair and rerun the affected gates or
report the blocker without switching or claiming completion. Distinguish
pre-existing limitations from regressions.

Repository documentation, repository-only skills, non-distributed tools, and
changes exclusive to another host need checks and a commit, not unrelated local
activation. For another host, locally evaluate changed attributes or build the
affected output as appropriate. Do not routinely run pre-change evaluations,
full before/after comparisons, `nix flake check`, or every host's build.

Report commit status and, when applicable, live activation and boot-default
persistence separately from publication. A failed or unavailable push does not
undo completed local work.

## Package inputs and checkout paths

For GitHub packages owned by `keewai704`, explicitly select `main` and pin the
revision and hash. Use `?ref=main` for Git flake inputs and refresh from `main`;
do not rely on the remote default branch.

Outside the repository root, use `git -C` and absolute flake references to the
actual checkout, normally `/home/keewai/nixos-configuration` and
`/home/keewai/nixos-configuration#<runtime-host>`.

## Orange web exposure

Orange's user-facing HTTP, HTTPS, and WebSocket services follow:

`tailnet client -> Tailscale Serve HTTPS -> loopback nginx -> loopback application`

- HTTPS 443 is the only external web entry point, including WebSockets and
  TLS-terminated TCP. Other web/backend ports are loopback connections only.
- Bind applications to `127.0.0.1` or a Unix socket, not LAN/wildcard addresses.
  Normally add a path to `orange.tail1e65cd.ts.net` and reuse Serve's HTTPS 443
  forwarding to `127.0.0.1:8000`. Do not point Serve directly at an application or
  open backend ports in the general firewall or `tailscale0` rules.
- Configure the canonical tailnet HTTPS external/base URL where supported.
  Preserve original host, scheme, and client IP; enable nginx WebSocket forwarding
  when required.
- For applications without subpath support, use a patch, client rebuild, or safe
  adapter. If no safe 443 solution exists, leave the service unexposed and report
  the blocker.
- Check the canonical URL, redirects, assets, and required WebSockets; use `ss`
  for loopback-only backends and `tailscale serve status` for the single HTTPS
  443 web listener.

Apply and live-check Orange changes only when the verified runtime host is
`orange`. On other hosts, validate its configuration locally without remote
access or deployment.
