import json
import os
import sys
from pathlib import Path

key = os.environ.get("TINYFISH_API_KEY")
if not key:
    config = Path.home() / ".tinyfish/config.json"
    try:
        key = json.loads(config.read_text()).get("api_key")
    except (OSError, ValueError):
        key = None
if not key:
    sys.exit("TinyFish API key missing: set TINYFISH_API_KEY or save api_key in ~/.tinyfish/config.json")
print(json.dumps({"Authorization": f"Bearer {key}"}))
