import hashlib
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
mount = '/tv'

def replace(path, old, new, count=1):
    text = path.read_text()
    actual = text.count(old)
    if actual != count:
        raise RuntimeError(f'{path}: expected {count} occurrences of {old!r}, found {actual}')
    path.write_text(text.replace(old, new))

startup = root / 'server/KonomiTV.py'
text = startup.read_text()
start = text.index('    # カスタム HTTPS 証明書/秘密鍵が指定されているとき\n')
end = text.index('    # Uvicorn の設定\n', start)
text = text[:start] + text[end:]
text = text.replace('import atexit\n', '').replace('import subprocess\n', '')
text = text.replace("        host = '127.0.0.77',", "        host = '127.0.0.1',")
text = text.replace('        port = CONFIG.server.port + 10,', "        port = CONFIG.server.port,\n        root_path = '/tv',\n        proxy_headers = True,\n        forwarded_allow_ips = '127.0.0.1',")
text = text.replace('    # HTTPS リバースプロキシを終了\n    reverse_proxy_process.terminate()\n\n', '')
if 'reverse_proxy_process' in text or 'subprocess.' in text and 'subprocess.CREATE' in text:
    raise RuntimeError('Akebi startup removal failed')
startup.write_text(text)
replace(startup, '    for library_name, library_path in LIBRARY_PATH.items():',
        "    for library_name, library_path in LIBRARY_PATH.items():\n"
        "        if library_name in ['Akebi', 'NVEncC', 'VCEEncC', 'rkmppenc']:\n"
        "            continue")

config = root / 'server/app/config.py'
text = config.read_text()
start = text.index('        if (port + 10) in used_ports:\n')
end = text.index('        return port', start)
text = text[:start] + text[end:]
config.write_text(text)
replace(root / 'server/app/routers/MaintenanceRouter.py', "valid_host = f'127.0.0.77:{Config().server.port + 10}'", "valid_host = f'127.0.0.1:{Config().server.port}'")
replace(root / 'server/app/routers/NiconicoRouter.py', "request.headers.get('Origin', f'https://{request.url.netloc}').rstrip('/') + '/'", "request.headers.get('Origin', f'https://{request.url.netloc}').rstrip('/') + '/tv/'")
replace(root / 'server/app/routers/NiconicoRouter.py', "'server': f'https://{request.url.netloc}/',", "'server': f'https://{request.url.netloc}/tv/',")

client = root / 'client'
replace(client / 'vite.config.mts', 'export default defineConfig({', "export default defineConfig({\n    base: '/tv/',")
replace(client / 'src/utils/Utils.ts', '${self.location.host}/api', '${self.location.host}/tv/api')
replace(client / 'src/services/OfflineVideoStorage.ts', "'/local/offline-videos/'", "'/tv/local/offline-videos/'")
replace(client / 'src/sw.ts', r'denylist: [/^\/api/, /^\/cdn-cgi/]', r'denylist: [/^\/tv\/api/, /^\/tv\/cdn-cgi/]')
router = client / 'src/router/index.ts'
replace(router, "        {\n            path: '/',\n            redirect: '/tv/',\n        },\n", '')
replace(router, "            path: '/tv/',", "            path: '/tv/',\n            alias: '/',")
for path in [client / 'index.html', client / 'vite.config.mts', *list((client / 'src').rglob('*'))]:
    if path.is_file() and path.suffix in {'.vue', '.ts', '.mts', '.scss', '.css', '.html'}:
        text = path.read_text()
        path.write_text(text.replace('/assets/', '/tv/assets/'))

dist = client / 'dist'
main_entry = re.search(r'<script[^>]+src="/([^"]+)"', (dist / 'index.html').read_text()).group(1)
for path in dist.rglob('*'):
    if not path.is_file() or path.suffix not in {'.js', '.css', '.html', '.webmanifest'}:
        continue
    text = path.read_text()
    text = text.replace('/assets/', '/tv/assets/')
    text = text.replace('${self.location.host}/api', '${self.location.host}/tv/api')
    text = text.replace('"/local/offline-videos/"', '"/tv/local/offline-videos/"')
    text = text.replace('"/manifest.webmanifest"', '"/tv/manifest.webmanifest"')
    text = text.replace('"/sw.js"', '"/tv/sw.js"')
    text = text.replace('scope:"/"', 'scope:"/tv/"')
    text = text.replace(r'denylist:[/^\/api/,/^\/cdn-cgi/]', r'denylist:[/^\/tv\/api/,/^\/tv\/cdn-cgi/]')
    if path == dist / main_entry:
        text, count = re.subn(r'(history:[\w$]+\()"/"(\),routes:)', r'\1"/tv/"\2', text)
        if count != 1:
            raise RuntimeError(f'{path}: router base changed upstream ({count})')
        old = 'routes:[{path:"/",redirect:"/tv/"},{path:"/tv/",name:"TV Home"'
        if text.count(old) != 1:
            raise RuntimeError(f'{path}: TV home route changed upstream')
        text = text.replace(old, 'routes:[{path:"/tv/",alias:"/",name:"TV Home"')
        text, count = re.subn(r'("modulepreload",[\w$]+=function\([\w$]+\)\{return)"/"\+', r'\1"/tv/"+', text)
        if count != 1:
            raise RuntimeError(f'{path}: Vite preload base changed upstream ({count})')
    if path.suffix == '.webmanifest':
        manifest = json.loads(text)
        manifest['scope'] = '/tv/'
        manifest['start_url'] = '/tv/'
        text = json.dumps(manifest, ensure_ascii=False, separators=(',', ':'))
    path.write_text(text)

worker = dist / 'sw.js'
text = worker.read_text()
def revision(match):
    entry = json.loads(match.group())
    file = dist / entry['url'].removeprefix('/tv/').lstrip('/')
    if not file.is_file():
        raise RuntimeError(f'Missing precache file: {file}')
    entry['revision'] = hashlib.sha256(file.read_bytes()).hexdigest()
    return json.dumps(entry, ensure_ascii=False, separators=(',', ':'))
text, count = re.subn(r'\{"revision":(?:null|"[^"\n]*"),"url":"[^"\n]+"\}', revision, text)
if count == 0:
    raise RuntimeError('Workbox precache manifest changed upstream')
worker.write_text(text)
