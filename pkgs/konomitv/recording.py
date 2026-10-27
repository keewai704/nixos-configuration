import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'server/app/metadata/RecordedScanTask.py'
text = path.read_text()
size_update = '                recording_info.file_size = file_size\n'
analyze = '                await self.processRecordedFile(file_path, original_file_path)\n'
if text.count(size_update) != 1 or text.count(analyze) != 2:
    raise RuntimeError('Recording change handling changed upstream')
text = text.replace(size_update, '')
path.write_text(text.replace(analyze, analyze + size_update, 1))
