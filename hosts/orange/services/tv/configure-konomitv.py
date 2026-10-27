import sys
from pathlib import Path

from ruamel.yaml import YAML

path = Path(sys.argv[1])
yaml = YAML()
config = yaml.load(path)
config.setdefault('tv', {})['max_alive_time'] = int(sys.argv[2])
temporary = path.with_suffix('.yaml.tmp')
with temporary.open('w') as stream:
    yaml.dump(config, stream)
temporary.chmod(path.stat().st_mode & 0o777)
temporary.replace(path)
