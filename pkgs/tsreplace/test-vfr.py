import json
import subprocess
import sys
import tempfile
from fractions import Fraction
from pathlib import Path


binary, ffmpeg, ffprobe = map(str, sys.argv[1:])
binary = str(Path(binary).resolve())


def timestamps(path):
    result = subprocess.run([ffprobe, '-v', 'error', '-select_streams', 'v:0',
                             '-show_streams', '-show_packets',
                             '-show_entries', 'stream=time_base:packet=pts',
                             '-of', 'json', str(path)], check=True, capture_output=True)
    info = json.loads(result.stdout)
    scale = Fraction(info['streams'][0]['time_base']) * 90000
    values = sorted(round(packet['pts'] * scale) for packet in info['packets'])
    return [value - values[0] for value in values]


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    source = root / 'source.ts'
    replacement = root / 'filtered.mp4'
    output = root / 'output.ts'
    for path, rate, options in [
        (source, '30000/1001', ['-c:v', 'mpeg2video', '-bf', '2', '-g', '30',
                              '-mpegts_service_id', '100']),
        (replacement, '60000/1001', ['-vf', 'select=gte(t\\,0.5)+not(mod(n\\,2))',
                                    '-fps_mode', 'vfr', '-c:v', 'libx265',
                                    '-x265-params', 'log-level=error:pools=1:frame-threads=1:bframes=2']),
    ]:
        subprocess.run([ffmpeg, '-nostdin', '-hide_banner', '-loglevel', 'error',
                        '-f', 'lavfi', '-i', f'testsrc2=size=96x64:rate={rate}:duration=1.001',
                        *options, '-y', str(path)], check=True)
    subprocess.run([binary, '-i', str(source), '-r', str(replacement), '-o', str(output),
                    '--service', '100'], check=True)
    expected, actual = timestamps(replacement), timestamps(output)
    if len(expected) != len(actual):
        raise AssertionError(f'Replacement frames lost: {len(expected)} -> {len(actual)}')
    if any(abs(before - after) > 2 for before, after in zip(expected, actual)):
        raise AssertionError('Variable frame timing changed during TS replacement')
    print(f'Preserved all {len(expected)} variable-rate replacement frames through EOF')
