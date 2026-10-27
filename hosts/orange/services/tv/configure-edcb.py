import configparser
import sys
from pathlib import Path

source = Path(sys.argv[1])
destination = Path(sys.argv[2])

def read(path):
    settings = configparser.RawConfigParser(strict=False)
    settings.optionxform = str
    settings.read(path, encoding='utf-8-sig')
    return settings

managed = read(source)
settings = read(destination)
for section in managed.sections():
    if not settings.has_section(section):
        settings.add_section(section)
    for key, value in managed.items(section):
        for existing in list(settings[section]):
            if existing.lower() == key.lower():
                settings.remove_option(section, existing)
        settings.set(section, key, value)

temporary = destination.with_suffix('.ini.new')
with temporary.open('w', encoding='utf-8') as output:
    settings.write(output, space_around_delimiters=False)
temporary.replace(destination)
