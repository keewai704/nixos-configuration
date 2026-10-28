import sys
from pathlib import Path

from ruamel.yaml import YAML

yaml = YAML()
managed = yaml.load(Path(sys.argv[1]))
path = Path(sys.argv[2])
config = yaml.load(path)
for section in ('general', 'server', 'tv', 'video', 'capture'):
    config.setdefault(section, {}).update(managed[section])
temporary = path.with_suffix('.yaml.tmp')
with temporary.open('w') as stream:
    yaml.dump(config, stream)
temporary.chmod(path.stat().st_mode & 0o777)
temporary.replace(path)
