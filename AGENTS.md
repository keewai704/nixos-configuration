# Repository working agreement

This file defines ownership, authorization, and completion requirements.
Parent model selection lives in `home/keewai/shared/pi/agent.nix`; Pi Web child
profiles live in `home/keewai/shared/pi/web-agents/`. Cross-project behavior and
skill routing live in `home/keewai/shared/pi/APPEND_SYSTEM.md`. Personal skills
live in `skills/`; repository-only skills live in `.agents/skills/`.
Use [README.md](README.md) for architecture, examples, and editing entry points
when those details are relevant to the task.

## 1. Identify the execution host

Before inspecting live system state or performing host-dependent operations,
confirm that `hostnamectl --static` matches `/etc/hostname`; use `hostname` if
`hostnamectl` is unavailable. Reuse this confirmation while the environment is
unchanged. Recheck if the environment changes or host identity becomes uncertain.
A mismatch blocks host-dependent operations, not read-only source analysis.

Only the verified local host may be treated as the running system. Do not infer
its identity from repository paths, flake targets, instructions, previous
conversations, or configuration being edited.

Do not use SSH, mosh, or remote shells to inspect checkouts, edit, validate,
rebuild, deploy, or check runtime state on another host unless the current request
explicitly authorizes that host and remote operation. General repository access
does not grant remote access. Another host's declarative configuration may be
edited, formatted, evaluated, or built in this local checkout without connecting
to that host.

## 2. Match file names and responsibilities

Read the affected implementation and the callers or imports needed to understand
the change. Consult README.md when choosing a new location or resolving ownership;
reuse unchanged context already read.

- Put settings, scripts, documentation, and instructions where their name and path
  predict their purpose. Existing imports, convenient values, smaller diffs, or
  existing misplaced content do not justify adding unrelated responsibilities.
- If no suitable file exists, create a specifically named file in the responsible
  directory and connect its imports or references. Avoid vague `misc` or `utils`
  containers. Keep tightly coupled implementation together rather than splitting
  it to meet a line count or one-setting-per-file rule.
- Keep `hosts/<host>/default.nix` for imports and small host-wide settings.
  `modules/common.nix` contains only settings used by every host. Put substantial
  features and services in files named for them.
- Limit moves and renames to the requested scope; update all references and
  preserve existing behavior. Leave unrelated cleanup for another task.
- Before committing, check every changed file's responsibility and placement.
  Fix mismatches and briefly explain any non-obvious placement in the final report.
  Reviews should flag newly introduced responsibility mismatches too.

## 3. Prefer Home Manager for personal applications

Use Home Manager for personal applications, CLI tools, shell settings, user
services, and user files. Prefer suitable `programs.*` or `services.*` modules,
then `home.packages`. Declare these in `home/<user>/common.nix`, `shared/`, or
`desktop/`, not `hosts/`.

All hosts share the common profile. Desktop hosts also load the common desktop
profile through `modules/desktop.nix`; place GUI applications, session services,
themes, and desktop-only MCP servers there. Apply hardware-dependent differences
within that profile based on available capabilities. `modules/home-manager.nix`
owns the NixOS/Home Manager connection.

Before choosing system ownership, inspect the pinned NixOS and Home Manager
modules and upstream requirements. Preserve required boot/login integration,
daemons, kernel/drivers, udev, PAM, polkit, D-Bus activation, capability/setuid
wrappers, graphics infrastructure, and system font access. Keep necessary OS and
device integration in `hosts/<host>/` or a genuinely shared system module;
clients and daemons may have different owners.

Do not disable an integration module or force its package list empty merely to
move executables. Replace it only when all required integration is explicitly
preserved. After changing ownership, verify affected profiles, plugins, native
messaging, MIME handlers, autostart, session integration, and device access.
Explain the specific integration requiring each affected system-side application
in the final report. Build-only and service-internal dependencies belong with
their consumer rather than the personal interactive application set.

Home Manager controls ownership, not sandboxing or execution privileges. This
repository uses `useUserPackages = true`, installs user packages under
`/etc/profiles/per-user/<user>`, and still deploys through NixOS activation.
Do not describe a package move as privilege reduction or root-free deployment.

## 4. Respect sources and authorization

Edit Nix-managed sources, not generated files under `/home/keewai/.pi/agent` or
`/home/keewai/.agents/skills`. Write agent instructions, prompt templates, and
skills in English; respond to the user in their language.

Do not create repository-local `checks/` or `docs/` directories, standalone
check suites, or standalone documentation files. Keep validation guidance in
`.agents/skills/nixos-validation/SKILL.md`, not scripts or per-topic test
collections. Keep repository policy and navigation in AGENTS.md and README.md.
This restriction does not prohibit reading upstream documentation. Use disposable
validation commands and build tools; existing package-local tests and upstream
build tests are allowed. Do not add code comments; preserve functional syntax
such as shebangs and completion directives.

A change request authorizes the necessary local edits, disposable validation,
repairs caused by the change, commits, and local activation under section 5.
Do not ask for approval again at each step. Audit/advice requests authorize
inspection and recommendations, with only separately requested changes applied.
Unrelated changes and remote operations are not implied. Push, publication,
private-data uploads, and destructive actions require authorization covering the
specific operation.

If blocked, complete independent work that remains authorized and useful, then
report the concrete blocker and unfinished scope. Do not broaden authority or
fix unrelated problems to force completion.

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
