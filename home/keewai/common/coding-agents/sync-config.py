import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

home = Path.home()
state_dir = Path(os.environ.get("XDG_STATE_HOME", home / ".local/state")) / "coding-agents"
state_file = state_dir / "mcp-servers.json"
claude_file = home / ".claude.json"
pi_dir = Path(os.environ.get("PI_CODING_AGENT_DIR", home / ".pi/agent"))
pi_auth_file = pi_dir / "auth.json"
pi_mcp_file = pi_dir / "mcp.json"
pi_blackhole_file = pi_dir / "pi-blackhole" / "pi-blackhole-config.json"
codex_file = Path(os.environ.get("CODEX_HOME", home / ".codex")) / "config.toml"
jaq = sys.argv[4]


def write_atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def write_json(path, data):
    write_atomic(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def load_json(path):
    return json.loads(path.read_text()) if path.exists() else {}


def merge_json(path, values):
    data = load_json(path)
    data.update(values)
    write_json(path, data)


def helper_fails(command):
    try:
        return subprocess.run(command, shell=True, capture_output=True, timeout=30).returncode != 0
    except (OSError, subprocess.SubprocessError):
        return True


def load_state():
    if not state_file.exists():
        return {}
    data = json.loads(state_file.read_text())
    return data if isinstance(data, dict) else {"claude": data}


def sync_servers(path, servers, stale):
    data = load_json(path)
    current = data.get("mcpServers", {})
    for name in stale:
        current.pop(name, None)
    current.update(servers)
    if current:
        data["mcpServers"] = current
    else:
        data.pop("mcpServers", None)
    write_json(path, data)


def sync_claude_and_pi(servers, unusable):
    state = load_state()
    for target, path in (("claude", claude_file), ("pi", pi_mcp_file)):
        declared = servers[target]
        usable = {name: server for name, server in declared.items() if name not in unusable}
        stale = set(state.get(target, declared)) - usable.keys()
        if usable or stale:
            sync_servers(path, usable, stale)
        state[target] = sorted(usable)
    write_json(state_file, state)


def sync_codex(unusable):
    if not unusable or not codex_file.exists():
        return
    expression = " | ".join(f"del(.mcp_servers[{json.dumps(name)}])" for name in sorted(unusable))
    result = subprocess.run(
        [jaq, "--from", "toml", "--to", "toml", expression, codex_file],
        check=True,
        capture_output=True,
        text=True,
    )
    write_atomic(codex_file, result.stdout)


merge_json(pi_auth_file, json.loads(Path(sys.argv[2]).read_text()))
merge_json(pi_blackhole_file, json.loads(Path(sys.argv[3]).read_text()))

document = json.loads(Path(sys.argv[1]).read_text())
unusable = {name for name, command in document["checks"].items() if helper_fails(command)}
sync_claude_and_pi(document["servers"], unusable)
sync_codex(unusable)
