# Repository working agreement

Complete the requested change through the applicable checks, commit, and local
deployment below. Keep going when the next step is authorized; ask only for a
decision that changes the outcome, scope, or authority. Audits remain read-only.
When blocked, finish independent work and report the blocker and unfinished scope.

Use [README.md](README.md) for architecture and editing entry points when needed,
not as a mandatory pre-read. Ownership:

- `home/keewai/shared/pi/agent.nix`: Pi model and runtime defaults.
- `home/keewai/shared/pi/subagents.nix` and `pkgs/pi-web/`: native CLI/Web delegation.
- `home/keewai/shared/pi/APPEND_SYSTEM.md`: cross-project behavior and skill routing.
- `skills/`: distributed personal skills; `.agents/skills/`: repository-only skills.

## 1. Identify the execution host

Before live-state inspection or host-dependent work, confirm that
`hostnamectl --static` matches `/etc/hostname` (`hostname` is the fallback).
Reuse the result until the environment or identity becomes uncertain. A mismatch
blocks host-dependent work, not read-only source analysis. Paths, flake targets,
and previous conversations are not evidence of the running host.

SSH, mosh, and remote shells require explicit authorization for that host and
operation. Another host's configuration may be edited, evaluated, or built
locally without connecting to it. Never activate another host's output locally.

## 2. Match file names and responsibilities

Read the affected implementation and relevant callers/imports; reuse unchanged
context. Put content where its name and path predict its purpose. Existing
misplacement, convenient imports, or a smaller diff do not justify unrelated
responsibilities. Create a specifically named file when needed, keeping tightly
coupled code together rather than splitting by line count.

`hosts/<host>/default.nix` is for imports and small host-wide settings;
`modules/common.nix` is only for settings used by every host. Substantial features
belong in named modules. Scope moves and renames to the task and update callers.
Review placement before committing and explain non-obvious choices in the report.

## 3. Prefer Home Manager for personal applications

Personal applications, CLI tools, shell settings, user services, and user files
belong in `home/<user>/common.nix`, `shared/`, or `desktop/`. Prefer suitable
`programs.*`/`services.*` modules, then `home.packages`, not `hosts/`.

Every host loads the common profile. `modules/desktop.nix` adds the shared
desktop profile for GUI apps, session services, themes, and desktop-only MCP
servers; express hardware differences there by capability.
`modules/home-manager.nix` owns the NixOS/Home Manager connection.

For ownership changes, inspect the pinned modules and upstream requirements.
Preserve boot/login, daemon, kernel/driver, udev, PAM, polkit, D-Bus,
capability/setuid, graphics, and system-font integration. Required OS/device
integration stays in a host or genuinely shared system module. Do not disable
integration modules or empty package lists merely to move executables unless all
integration is explicitly replaced. Clients and daemons may have different owners;
build-only and service-internal dependencies stay with their consumer.

Verify affected profiles, plugins, native messaging, MIME handlers, autostart,
session integration, and device access after an ownership change. Explain why
each affected system-side application needs that integration. Home Manager uses
`useUserPackages = true` and `/etc/profiles/per-user/<user>` here; deployment still
uses NixOS activation. Moving a package is not sandboxing or privilege reduction.

## 4. Respect sources and authorization

Edit Nix-managed sources, not generated files under `/home/keewai/.pi/agent` or
`/home/keewai/.agents/skills`. Write agent instructions, prompt templates, and
skills in English; respond to the user in their language.

Keep policy and navigation in AGENTS.md and README.md, and validation guidance in
`.agents/skills/nixos-validation/SKILL.md`. Do not add repository-local `checks/`
or `docs/`, standalone check suites or documentation files. Upstream documentation,
disposable validation, existing package-local tests, and upstream build tests are
allowed. Do not add code comments; preserve shebangs and completion directives.

A change request authorizes necessary local edits, disposable validation, repairs
caused by the change, commits, and section 5 activation without repeated approval.
Audit/advice requests authorize inspection and recommendations, not edits.
Unrelated work, remote operations, push/publication, private-data uploads, and
destructive actions need authorization covering the specific operation.

## 5. Validate, commit, and apply when the local host is affected

For every repository change:

1. Inspect Git status, unstaged changes, and staged changes before editing. Do not
   format, stage, stash, reset, or delete unrelated changes. Use an isolated
   worktree if the index is in use or unrelated changes could affect evaluation or
   activation; report the specific blocker if isolation is unavailable.
   For host-dependent work, record the verified runtime host and require its
   `nixosConfigurations.<runtime-host>` output. Never substitute another host.
2. Use [nixos-validation](.agents/skills/nixos-validation/SKILL.md) for the smallest
   appropriate checks. Format only task files. Stage new files before Git-flake
   checks and inspect the task-only staged diff. Use `--no-write-lock-file` unless
   input updates are requested. Reuse passing checks with unchanged relevant
   inputs; repeat or broaden them only for changes, failures, or unresolved
   concerns. Do not routinely run pre-change evaluations, before/after comparisons,
   `nix flake check`, or every host's build.
3. Commit all intended changes without unrelated user changes, and confirm no
   task changes remain uncommitted.
4. Determine local impact from the changed files and their imports. If the commit
   affects the runtime host's evaluated configuration, deployed files, or services,
   record the expected store path and relevant runtime baseline, then run
   `sudo nixos-rebuild test --flake .#<runtime-host>` on the committed state.
   Use its evaluation/build rather than prebuilding the same output or repeating
   equivalent evaluations. Pi and personal skills distributed from `skills/`
   affect every host. Never live-test another host's output.
5. After a successful `test`, check local network connectivity, failed system/user
   units, and the behavior of every affected service. New failures or regressions
   block `switch`.
6. Only after `test` and runtime checks pass, run
   `sudo nixos-rebuild switch --flake .#<runtime-host>` locally.
7. After `switch`, repeat the network and affected-service checks. Confirm that
   both the running system and boot-default system match the store path of the
   tested, committed configuration.

Formatting, appropriate checks, and a complete task commit are always required.
Activation and each post-activation runtime check are separate mandatory gates
only when the local host is affected; a previous passing check does not replace
these gates. Repository documentation, `.agents/skills/`, non-distributed tools,
and changes exclusive to another host require checks and a commit, not unrelated
local activation. For another host, locally evaluate the changed attributes or
build the affected output, whichever the change requires.

If `test` or a runtime gate fails, do not switch or claim completion. Repair the
change and rerun affected gates, or report the blocker. Distinguish pre-existing
limitations from regressions; they do not excuse verifying required behavior.
Report commit status and, when applicable, both live activation and boot-default
persistence. Keep implementation, local deployment, and publication outcomes
separate; unavailable or failed push does not undo completed local work.

## 6. Package sources and working directories

For packages from GitHub repositories owned by `keewai704`, explicitly select
`main` and pin the revision and hash. Use `?ref=main` for Git flake inputs and
refresh from `main` when updating; do not rely on the remote default branch.

Outside the repository root, use `git -C` and absolute flake references pointing
to the actual checkout. For the usual checkout these are
`git -C /home/keewai/nixos-configuration` and
`/home/keewai/nixos-configuration#<runtime-host>`.

## 7. Orange web exposure

User-facing HTTP, HTTPS, and WebSocket services must follow:

`tailnet client -> Tailscale Serve HTTPS -> loopback nginx -> loopback application`

- Expose only HTTPS 443 as the external web entry point. Do not expose HTTP,
  HTTPS, WebSockets, TLS-terminated TCP, or application backends on other external
  ports. Loopback ports are internal proxy connections only.
- Bind applications to `127.0.0.1` or a Unix socket, not LAN or wildcard addresses.
- Normally add a dedicated path to the existing `orange.tail1e65cd.ts.net` nginx
  virtual host. Reuse Tailscale Serve's HTTPS 443 forwarding to `127.0.0.1:8000`.
  Do not connect Serve directly to an application or open backend ports in either
  the general firewall or `tailscale0` rules.
- Configure the canonical tailnet HTTPS external/base URL when supported.
  Preserve the original host, scheme, and client IP; enable nginx WebSocket
  forwarding when needed.
- If subpaths are unsupported, use a patch, client rebuild, or safe adapter rather
  than another external port. If no safe 443 solution exists, leave the service
  unexposed and report the blocker.
- Verify the canonical URL, redirects, static assets, and required WebSockets.
  Use `ss` to confirm loopback-only backends and `tailscale serve status` to confirm
  a single HTTPS 443 web listener.

Apply these changes and perform their live checks only when the verified runtime
host is `orange`. On other hosts, validate Orange's configuration locally without
remote access or deployment.
