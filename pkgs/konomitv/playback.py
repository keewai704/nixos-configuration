import re
import sys
from pathlib import Path

root = Path(sys.argv[1])


def replace(path, old, new):
    text = path.read_text()
    if text.count(old) != 1:
        raise RuntimeError(f'{path}: expected one occurrence of {old!r}')
    path.write_text(text.replace(old, new))


replace(root / 'client/src/stores/SettingsStore.ts',
        'tv_low_latency_mode_cellular: false,',
        'tv_low_latency_mode_cellular: true,')

bundles = [path for path in (root / 'client/dist/assets').glob('*.js')
           if 'tv_low_latency_mode_cellular:!1' in path.read_text()]
if not bundles:
    raise RuntimeError('Mobile low-latency defaults changed upstream')
for bundle in bundles:
    replace(bundle, 'tv_low_latency_mode_cellular:!1', 'tv_low_latency_mode_cellular:!0')

migration = '''<script>
try {
    const key = 'KonomiTV-Settings';
    const migration = 'KonomiTV-LowLatency-v1';
    if (localStorage.getItem(migration) !== '1') {
        const settings = JSON.parse(localStorage.getItem(key) || '{}');
        settings.tv_low_latency_mode_cellular = true;
        localStorage.setItem(key, JSON.stringify(settings));
        localStorage.setItem(migration, '1');
    }
} catch {}
</script>
'''
for path in [root / 'client/index.html', root / 'client/dist/index.html']:
    replace(path, '</head>', migration + '</head>')

controller = root / 'client/src/services/player/PlayerController.ts'
replace(controller,
        'let api_quality = `${quality_name}${hevc_suffix}`;',
        "let api_quality = `${quality_name}${quality_name === '240p' ? '' : hevc_suffix}`;")
replace(controller,
        'if (is_hevc_10bit_playback === true) {',
        "if (is_hevc_10bit_playback === true && quality_name !== '240p') {")

pattern = re.compile(
    r'(?P<start>,[\w$]+=(?P<quality>[\w$]+)=>\{let (?P<api>[\w$]+)=)'
    r'`\$\{(?P=quality)}\$\{(?P<suffix>[\w$]+)}`;return '
    r'(?P<tenbit>[\w$]+)===!0&&\((?P=api)\+="-10bit"\)'
)


def compatible_quality(match):
    quality = match['quality']
    suffix = match['suffix']
    return (match['start'] + f'`${{{quality}}}${{{quality}==="240p"?"":{suffix}}}`;return '
            f'{quality}!=="240p"&&{match["tenbit"]}===!0&&({match["api"]}+="-10bit")')


matches = 0
for bundle in (root / 'client/dist/assets').glob('*.js'):
    text, count = pattern.subn(compatible_quality, bundle.read_text())
    if count:
        bundle.write_text(text)
        matches += count
if matches != 1:
    raise RuntimeError(f'Expected one streaming quality builder, found {matches}')
