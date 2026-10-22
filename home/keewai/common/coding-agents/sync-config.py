import json
import os
import sys
import tempfile
from pathlib import Path

home = Path.home()
state_dir = Path(os.environ.get("XDG_STATE_HOME", home / ".local/state")) / "coding-agents"
state_file = state_dir / "mcp-servers.json"
claude_file = home / ".claude.json"


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


servers = json.loads(Path(sys.argv[1]).read_text())
previous = set(json.loads(state_file.read_text())) if state_file.exists() else set()
stale = previous - servers.keys()
if servers or stale:
    sync_claude(servers, stale)
write_atomic(state_file, json.dumps(sorted(servers)) + "\n")
