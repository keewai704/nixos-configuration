import json
import os
import sys
import tempfile
import urllib.request

MODELS = "https://opencode.ai/inference/go/v1/models"
PREFIX = "opencode-go/"

settings_path = sys.argv[1]

request = urllib.request.Request(MODELS, headers={"User-Agent": "opencode-go-model-sync/1.0"})
with urllib.request.urlopen(request, timeout=30) as response:
    models = json.load(response)["data"]

options = [
    {
        "model": PREFIX + model["id"],
        "label": model.get("name") or model["id"],
        "description": "OpenCode Go",
    }
    for model in models
    if model.get("type") == "chat" and model.get("capabilities", {}).get("tools", {}).get("supported")
]
if not options:
    sys.exit("OpenCode Go returned no chat models with tool support")

try:
    with open(settings_path) as f:
        settings = json.load(f)
except FileNotFoundError:
    settings = {}

if settings.get("modelPicker") == {"options": options}:
    sys.exit(0)
settings["modelPicker"] = {"options": options}

directory = os.path.dirname(settings_path)
fd, temporary = tempfile.mkstemp(dir=directory, prefix=".settings.json.")
try:
    with os.fdopen(fd, "w") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(temporary, settings_path)
except BaseException:
    os.unlink(temporary)
    raise
