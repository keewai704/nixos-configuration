# Development and deployment

[AGENTS.md](../AGENTS.md) is the policy for repository preparation, required
checks, commits, and conditional local activation. This page supplies command
examples for those stages; it does not add a second set of completion gates.
Use the [check-selection table](../AGENTS.md#select-the-required-checks) for the
current change, and read the relevant host guide when choosing live checks.

## Establish the runtime and worktree

At the start of a task, confirm the local execution host. Reuse the result while
the environment is unchanged; do not infer it from a checkout or target name.

```console
runtime_host="$(hostnamectl --static 2>/dev/null || hostname)"
etc_host="$(tr -d '\r\n' < /etc/hostname)"
test "$runtime_host" = "$etc_host"

flake_host="$(
  nix eval --raw --no-write-lock-file \
    ".#nixosConfigurations.$runtime_host.config.networking.hostName"
)"
test "$runtime_host" = "$flake_host"

git status --short --branch
git diff
git diff --cached
```

Run commands from the actual checkout, or use `git -C /absolute/checkout`
and `/absolute/checkout#...` flake references. Use an isolated worktree when
the index is occupied or unrelated edits can affect evaluation or activation.
The runtime-host and remote-access boundaries remain those in AGENTS.md.

## Format, analyze, and build what changed

For changed Nix files, name each task file explicitly:

```console
nix fmt --no-write-lock-file -- path/to/changed.nix
git diff --check
```

Run static analysis appropriate to the changed code. For example, use the
pinned `statix` and `deadnix` packages for Nix declarations, shell syntax and
ShellCheck for shell logic, and the existing package or service checks for
behavior. Do not format or stage unrelated files.

Stage new task files before flake evaluation so Git flakes include them:

```console
git add -- path/to/task-file path/to/new-task-file
git diff --cached
nix flake check --no-write-lock-file
```

A normal flake check already evaluates the flake. Use `--no-build` only when
diagnosing evaluation separately. The flake includes Orange's backup-freshness
and alert-state regression tests; those use temporary local data and send no
alerts.

Build all affected configurations from the AGENTS.md table. For a Citrus system
module change, this includes the VM that imports Citrus:

```console
for target_host in citrus citrus-vm; do
  nix build ".#nixosConfigurations.$target_host.config.system.build.toplevel" \
    --no-link --no-write-lock-file
done
```

For inputs, shared Home Manager settings, Codex, skills, or other modules used
by all hosts, include `orange` as well. For a
VM-only or Orange-only change, build only that affected host. Build changed
package outputs too. On memory-constrained hosts, run Nix evaluations and
builds sequentially; `max-jobs` does not limit separate evaluator processes.

Reuse successful results for unchanged inputs. Documentation that is not
deployed needs whitespace, link, and consistency checks; personal skill files
are deployed and also require publication and affected-host checks.

## Commit and determine live scope

```console
git diff --cached --check
git commit
git status --short
```

Confirm that all intended changes are committed and unrelated work is intact.
The commit gate does not authorize push. Follow explicit or continuing
authorization for publication and report its status separately.

If the change does not affect the confirmed runtime host's configuration,
deployed files, or services, stop after checks and commit, and report that live
activation did not apply. Otherwise, record the expected committed system and
the relevant networking/service baseline before applying it.

## Test, check health, and switch

Resolve the expected store path; a previously built identical output is reused:

```console
tested_system="$(
  nix build ".#nixosConfigurations.$runtime_host.config.system.build.toplevel" \
    --no-link --no-write-lock-file --print-out-paths
)"
sudo nixos-rebuild test --flake ".#$runtime_host" --no-write-lock-file
test "$(readlink -f /run/current-system)" = "$tested_system"
```

After `test`, verify ordinary network connectivity and every affected service.
Use the [Citrus](citrus.md#verification),
[VM](citrus-vm.md#access-and-deployment), or [Orange](orange.md#verification) checks
relevant to the change. Useful observations include:

```console
systemctl --failed --no-legend
systemctl is-active NetworkManager tailscaled sshd
nmcli -t -f STATE,CONNECTIVITY general
getent ahostsv4 cache.nixos.org
tailscale status
```

Compare with the pre-activation baseline and required behavior. A fresh VM may
still need the separate Tailscale login documented in its setup guide; report
that existing limitation rather than claiming tailnet connectivity. If the
change requires tailnet access, authentication and that connectivity are
required before switching. New failures and failures of required behavior
block `switch`.

Only after the test and relevant health checks pass:

```console
sudo nixos-rebuild switch --flake ".#$runtime_host" --no-write-lock-file
test "$(readlink -f /run/current-system)" = "$tested_system"
test "$(readlink -f /nix/var/nix/profiles/system)" = "$tested_system"
```

Repeat networking and affected-service checks after `switch`. Report the
commit, running-system activation, boot-default match, publication status, and
any remaining limitations. Do not activate another host's output.

## References for sensitive changes

- Hardware/storage changes: preserve host-specific UUIDs, filesystems,
  bootloader settings, and state versions. See
  [Orange's storage rules](orange.md#storage-is-non-destructive) when relevant.
- Secrets: commit encrypted `.age` files only, with recipients in
  `secrets/secrets.nix`; never print plaintext or put it in the Nix store.
- Orange web services: follow [web ingress](orange.md#web-ingress) and the
  AGENTS.md port-443 topology.
