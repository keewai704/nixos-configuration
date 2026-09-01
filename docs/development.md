# Development and deployment

This is the canonical human workflow for every change to this repository. It
preserves the same scope-aware completion gates as `AGENTS.md`: identify the
local host, validate, and commit every change; test, health-check, and switch
only when the committed change affects that local host.

## Runtime-host boundary

Before reading repository files, editing, evaluating, building, deploying, or
checking live services, identify the machine that is executing the commands:

```console
runtime_host="$(hostnamectl --static 2>/dev/null || hostname)"
etc_host="$(tr -d '\r\n' < /etc/hostname)"

if [ "$runtime_host" != "$etc_host" ]; then
  printf 'hostname mismatch: runtime=%s /etc/hostname=%s\n' "$runtime_host" "$etc_host" >&2
  exit 1
fi

flake_host="$(
  nix eval --raw --no-write-lock-file \
    ".#nixosConfigurations.$runtime_host.config.networking.hostName"
)"
if [ "$runtime_host" != "$flake_host" ]; then
  printf 'no matching flake host for %s\n' "$runtime_host" >&2
  exit 1
fi

printf 'local runtime host: %s\n' "$runtime_host"
```

The confirmed runtime host is the only live system in scope. A repository path,
flake target, or host whose files are being edited does not make that machine
the live host.

Do not use SSH, mosh, a remote shell, or another remote-execution mechanism to
inspect, change, rebuild, deploy, or health-check another host. Editing another
host's declarative files is allowed, but its checks are limited to local
formatting, evaluation, and builds. Remote work is allowed only when the user
explicitly requests that exact host and operation.

## Preserve the worktree

Start by recording existing work:

```console
git status --short --branch
git diff
git diff --cached
```

Existing modifications and untracked files belong to their owner. Do not
rewrite, stage, commit, stash, reset, or delete unrelated work. If an unrelated
tracked change can affect evaluation or activation, isolate the task safely or
stop; do not claim that a dirty configuration was tested as the committed task.

Place new code according to the [repository map](../README.md#layout). Keep
`hosts/<host>/configuration.nix` focused on imports and small host-wide
settings.

## Format, analyze, evaluate, and build

Format intended Nix changes and inspect the result before continuing:

```console
nix fmt --no-write-lock-file -- path/to/changed.nix
nix fmt --no-write-lock-file -- --ci path/to/changed.nix
git diff --check
```

List every intended Nix file in these commands. A repository-wide `nix fmt` is
safe only after confirming that the worktree contains no unrelated changes.

Do not run a repository-wide formatter over unrelated dirty files. Isolate the
task first when formatting would rewrite someone else's changes.

Run static evaluation and the full flake check:

```console
nix flake check --no-build --no-write-lock-file
nix flake check --no-write-lock-file
```

Evaluate and build every affected host explicitly. A change to `flake.nix`,
`modules/common.nix`, or another module shared by both hosts requires both
builds:

```console
for target_host in citrus-vm orange; do
  nix eval --no-write-lock-file \
    ".#nixosConfigurations.$target_host.config.system.build.toplevel.drvPath"
  nix build ".#nixosConfigurations.$target_host.config.system.build.toplevel" \
    --no-link \
    --no-write-lock-file
done
```

Narrowly host-specific changes may build only that host. Package changes also
build the package and every host that consumes it:

```console
nix build .#chatgpt-desktop --no-link --no-write-lock-file
nix build .#cua-driver --no-link --no-write-lock-file
```

| Change scope | Minimum explicit builds |
| --- | --- |
| `flake.nix`, `modules/common.nix`, or a module used by both hosts | `citrus-vm` and `orange` |
| Citrus host, desktop, ChatGPT, MCP, CUA, or skills | `citrus-vm` and any changed package output |
| Orange host, service, monitoring, or maintenance | `orange` and any changed package |
| Configuration used only by another host | That host; do not activate it or an unrelated local host |
| Documentation only | Formatting and link checks appropriate to the files; no live activation |

Never treat a successful build for one host as authorization to activate it on
a different runtime host.

## Commit the intended change

Review and stage explicit task paths; do not use a broad stage command in a
mixed worktree:

```console
git diff -- path/to/task-file
git add -- path/to/task-file
git diff --cached
git commit
git status --short
```

Every intended task change must be committed, and no task-related change may
remain uncommitted. Do not include unrelated changes in the commit.

## Test the committed generation locally

Run the remaining live gates only when the committed change affects the
confirmed runtime host's evaluated configuration, deployed files, or services.
For documentation-only, undeployed tooling, or another-host-only changes,
report that live activation was not applicable and stop after the commit.

Resolve the expected store path from the committed configuration, then activate
it temporarily on the confirmed runtime host:

```console
tested_system="$(
  nix build \
    ".#nixosConfigurations.$runtime_host.config.system.build.toplevel" \
    --no-link \
    --no-write-lock-file \
    --print-out-paths
)"

sudo nixos-rebuild test --flake ".#$runtime_host" --no-write-lock-file
running_system="$(readlink -f /run/current-system)"
test "$running_system" = "$tested_system"
```

`nixos-rebuild test` changes the running generation without changing the boot
default. Never replace `$runtime_host` with another host.

Now verify networking and every affected service. At minimum:

```console
systemctl --failed --no-legend
systemctl is-active NetworkManager tailscaled sshd
tailscale status
```

Use the host-specific checks in the [Citrus guide](citrus-vm.md#verification)
or [Orange guide](orange.md#verification). If any build, activation, networking,
or service check fails, fix it and repeat the workflow. Do not run `switch`.

## Switch and verify persistence

Only after the temporary generation and health checks pass:

```console
sudo nixos-rebuild switch --flake ".#$runtime_host" --no-write-lock-file

running_system="$(readlink -f /run/current-system)"
boot_default_system="$(readlink -f /nix/var/nix/profiles/system)"
test "$running_system" = "$tested_system"
test "$boot_default_system" = "$tested_system"
```

Repeat all networking and affected-service checks after `switch`. When live
activation applies, completion requires all of the following:

- the intended change is committed;
- `test` succeeded against the local runtime host;
- networking and affected services passed before `switch`;
- `switch` succeeded;
- networking and affected services passed again;
- the running and boot-default systems both equal the tested store path.

Report the commit, whether the running system was updated, and whether the
tested configuration is the boot default. A failed gate means the work is not
complete.

## Change-specific safety

### Hardware and storage

Treat `hardware-configuration.nix`, disk UUIDs, filesystems, bootloader settings,
and state versions as host-specific. Review generated hardware changes rather
than copying them between hosts. Orange's existing storage disk has additional
non-destructive rules in the [Orange guide](orange.md#storage-is-non-destructive).

### Secrets

Store only encrypted `.age` files in Git. Recipients are declared in
`secrets/secrets.nix`. Never print plaintext secrets, place them in the Nix
store, or commit a decrypted value.

### Orange web services

Every HTTP, HTTPS, or WebSocket service must follow the Orange port-443 topology
described in the [Orange guide](orange.md#web-ingress). If a service cannot be
published safely at its canonical HTTPS path, leave it unpublished and report
the blocker.
