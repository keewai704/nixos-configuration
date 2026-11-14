import json
import os
import sys
from pathlib import Path

path = os.environ.get("TINYFISH_API_KEY_FILE")
try:
    key = Path(path).read_text().strip() if path else ""
except OSError:
    key = ""
if not key:
    sys.exit(f"TinyFish API key missing or empty: {path or 'TINYFISH_API_KEY_FILE'}")
print(json.dumps({"Authorization": f"Bearer {key}"}))
