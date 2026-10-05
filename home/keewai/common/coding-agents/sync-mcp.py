import json
import os
import sys
import tempfile
from pathlib import Path

import tomlkit

home = Path.home()
state_dir = Path(os.environ.get("XDG_STATE_HOME", home / ".local/state")) / "coding-agents"
state_file = state_dir / "mcp-servers.json"
claude_file = home / ".claude.json"
codex_file = Path(os.environ.get("CODEX_HOME", home / ".codex")) / "config.toml"


def write_atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def sync_claude(servers, stale):
    data = json.loads(claude_file.read_text()) if claude_file.exists() else {}
    current = data.get("mcpServers", {})
    for name in stale:
        current.pop(name, None)
    for name, server in servers.items():
        current[name] = {"type": "stdio", **server}
    if current:
        data["mcpServers"] = current
    else:
        data.pop("mcpServers", None)
    write_atomic(claude_file, json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def sync_codex(servers, stale):
    doc = tomlkit.parse(codex_file.read_text()) if codex_file.exists() else tomlkit.document()
    if "mcp_servers" not in doc:
        doc["mcp_servers"] = tomlkit.table(is_super_table=True)
    current = doc["mcp_servers"]
    for name in stale:
        current.pop(name, None)
    for name, server in servers.items():
        table = tomlkit.table()
        table["command"] = server["command"]
        table["args"] = server["args"]
        if server["env"]:
            table["env"] = server["env"]
        current[name] = table
    if not current:
        del doc["mcp_servers"]
    write_atomic(codex_file, tomlkit.dumps(doc).rstrip() + "\n")


servers = json.loads(Path(sys.argv[1]).read_text())
previous = set(json.loads(state_file.read_text())) if state_file.exists() else set()
stale = previous - servers.keys()
if not servers and not stale:
    sys.exit()

sync_claude(servers, stale)
sync_codex(servers, stale)
write_atomic(state_file, json.dumps(sorted(servers)) + "\n")
