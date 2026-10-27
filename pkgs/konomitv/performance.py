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
