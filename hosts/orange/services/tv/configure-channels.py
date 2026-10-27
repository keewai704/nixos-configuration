import json
import sys
from pathlib import Path

directory = Path(sys.argv[1])
policy = json.loads(Path(sys.argv[2]).read_text())
networks = set(policy['networks'])
services = {tuple(service) for service in policy['services']}

for path in [directory / 'ChSet5.txt', *directory.glob('BonDriver_*.ChSet4.txt')]:
    raw = path.read_bytes()
    if raw.startswith((b'\xff\xfe', b'\xfe\xff')):
        encoding = 'utf-16'
    else:
        encoding = 'utf-8-sig' if raw.startswith(b'\xef\xbb\xbf') else 'utf-8'
    try:
        text = raw.decode(encoding)
    except UnicodeDecodeError:
        encoding = 'cp932'
        text = raw.decode(encoding)
    output = []
    for line in text.splitlines(keepends=True):
        ending = line[len(line.rstrip('\r\n')):]
        fields = line.rstrip('\r\n').split('\t')
        start, flags = (2, (7, 8)) if path.name == 'ChSet5.txt' else (5, (10,))
        if len(fields) > max(flags):
            try:
                service = tuple(map(int, fields[start:start + 3]))
            except ValueError:
                service = ()
            if service and (service[0] in networks or service in services):
                for index in flags:
                    fields[index] = '0'
                line = '\t'.join(fields) + ending
        output.append(line)
    result = ''.join(output)
    if result != text:
        temporary = path.with_name(path.name + '.new')
        temporary.write_bytes(result.encode(encoding))
        temporary.chmod(path.stat().st_mode & 0o777)
        temporary.replace(path)
