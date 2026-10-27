import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

channels = json.loads(Path(sys.argv[1]).read_text())
expected = {(channel['channel'], sid) for channel in channels for sid in channel['services']}
missing = expected
for attempt in range(300):
    try:
        with urllib.request.urlopen('http://127.0.0.1:40772/api/services', timeout=1) as response:
            services = json.load(response)
    except (urllib.error.URLError, TimeoutError):
        time.sleep(1)
        continue
    found = {(service['channel']['channel'], service['serviceId']) for service in services
             if service['channel']['type'] == 'GR'}
    missing = expected - found
    if not missing:
        print(f'mirakc is ready with {len(expected)} terrestrial services')
        break
    time.sleep(1)
else:
    raise SystemExit(f'mirakc services are not ready: {sorted(missing)}')
