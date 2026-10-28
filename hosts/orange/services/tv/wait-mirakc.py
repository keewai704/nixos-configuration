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
        with urllib.request.urlopen(f'{sys.argv[2]}/api/services', timeout=1) as response:
            services = json.load(response)
    except (urllib.error.URLError, TimeoutError):
        time.sleep(1)
        continue
    found = {(service['channel']['channel'], service['serviceId']) for service in services
             if service['channel']['type'] == 'GR'}
    missing = expected - found
    available = expected & found
    if available:
        print(f'mirakc is ready with {len(available)} terrestrial services')
        break
    time.sleep(1)
else:
    raise SystemExit(f'mirakc services are not ready: {sorted(missing)}')
