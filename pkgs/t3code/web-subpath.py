import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
clients = list(root.glob("**/index.html"))
clients = [
    p.parent
    for p in clients
    if (p.parent / "assets").is_dir()
    and (p.parent / "manifest.webmanifest").is_file()
    and "T3 Code" in (p.parent / "manifest.webmanifest").read_text()
]
assert len(clients) == 1, clients
client = clients[0]
routers = 0
for path in (client / "assets").glob("*.js"):
    source = path.read_text()
    source, count = re.subn(
        r'(context:\{\},)(defaultPreload:[`\"\']intent[`\"\'])',
        r'\1basepath:"/t3",\2',
        source,
    )
    routers += count
    source = re.sub(r'([`\"\'])/assets/', r'\1/t3/assets/', source)
    source = re.sub(r'([`\"\'])assets/', r'\1t3/assets/', source)
    path.write_text(source)
assert routers == 1, routers
index = client / "index.html"
index.write_text(re.sub(r'((?:src|href)=")/(?!/)', r'\1/t3/', index.read_text()))
for path in (client / "assets").glob("*.css"):
    path.write_text(path.read_text().replace("url(/assets/", "url(/t3/assets/"))
manifest = client / "manifest.webmanifest"
data = json.loads(manifest.read_text())
for key in ("id", "start_url", "scope"):
    data[key] = "/t3/"
for icon in data.get("icons", []):
    icon["src"] = "/t3/" + icon["src"].lstrip("/")
manifest.write_text(json.dumps(data))
