import ast
import copy
import datetime
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import Mock

source = Path(sys.argv.pop(1)) / 'server/app/metadata/RecordedScanTask.py'
tree = ast.parse(source.read_text())
scanner = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == 'RecordedScanTask')
handler = copy.deepcopy(next(node for node in scanner.body if isinstance(node, ast.AsyncFunctionDef) and node.name == '__handleFileChange'))
for argument in handler.args.args:
    argument.annotation = None
handler.returns = None
processor = next(node for node in scanner.body if isinstance(node, ast.AsyncFunctionDef) and node.name == 'processRecordedFile')
assignments = [node for node in ast.walk(processor) if isinstance(node, ast.Assign) and
               any(isinstance(target, ast.Name) and target.id == 'is_recording' for target in node.targets)]
if len(assignments) != 1:
    raise RuntimeError('Recording metadata guard changed upstream')
assignment = assignments[0]
block = next(node for node in ast.walk(processor) if isinstance(node, ast.If) and
             isinstance(node.test, ast.Name) and node.test.id == 'is_recording')
guard = ast.parse('def can_analyze(self, file_path, file_size, now, existing_recorded_video_summary=None):\n    pass').body[0]
guard.body = [copy.deepcopy(assignment), copy.deepcopy(block), ast.Return(value=ast.Constant(value=True))]
namespace = dict(datetime=datetime.datetime, JST=datetime.timezone.utc, logging=Mock(), FileRecordingInfo=types.SimpleNamespace)
module = ast.fix_missing_locations(ast.Module(body=[handler, guard], type_ignores=[]))
exec(compile(module, str(source), 'exec'), namespace)


class RecordingPath:
    def __init__(self, size, modified):
        self.size = size
        self.modified = modified

    async def stat(self):
        return types.SimpleNamespace(st_size=self.size, st_mtime=self.modified.timestamp())


class RecordingChanges(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.now = datetime.datetime.now(datetime.timezone.utc)
        self.path = RecordingPath(2048, self.now)
        self.info = types.SimpleNamespace(file_size=1024, last_modified=self.now - datetime.timedelta(seconds=1),
            last_checked=self.now - datetime.timedelta(seconds=31), mtime_continuous_start_at=None)
        self.task = types.SimpleNamespace(_recording_files={self.path: self.info},
            UPDATE_THROTTLE_SECONDS=30, CONTINUOUS_UPDATE_THRESHOLD_SECONDS=60,
            CONTINUOUS_UPDATE_MAX_SECONDS=86400, RECORDING_MAX_AGE_SECONDS=10)
        self.analyzed = []
        self.existing = None
        namespace['logging'].reset_mock()

        async def process(path, original):
            if namespace['can_analyze'](self.task, path, path.size, self.now, self.existing):
                self.analyzed.append((path, original))

        self.task.processRecordedFile = process

    async def change(self):
        await namespace['__handleFileChange'](self.task, self.path, 'original.ts')
        namespace['logging'].error.assert_not_called()

    async def test_append_is_analyzed_without_false_idle_warning(self):
        await self.change()
        self.assertEqual(self.analyzed, [(self.path, 'original.ts')])
        self.assertEqual(self.task._recording_files[self.path].file_size, self.path.size)
        namespace['logging'].warning.assert_not_called()

    async def test_preallocated_recording_keeps_continuous_write_detection(self):
        self.path.size = self.info.file_size
        self.info.mtime_continuous_start_at = self.now - datetime.timedelta(seconds=120)
        await self.change()
        self.assertEqual(len(self.analyzed), 1)

    async def test_recent_preallocated_write_waits_for_continuous_update(self):
        self.path.size = self.info.file_size
        await self.change()
        self.assertEqual(self.analyzed, [])
        namespace['logging'].warning.assert_not_called()

    async def test_registered_recording_does_not_repeat_metadata_analysis(self):
        self.existing = types.SimpleNamespace(status='Recording')
        await self.change()
        self.assertEqual(self.analyzed, [])
        self.assertEqual(self.task._recording_files[self.path].file_size, self.path.size)

    async def test_new_recording_becomes_analyzable_when_appended(self):
        self.task._recording_files.clear()
        await self.change()
        self.assertEqual(self.analyzed, [])
        self.path.size += 1024
        self.path.modified += datetime.timedelta(seconds=1)
        await self.change()
        self.assertEqual(len(self.analyzed), 1)


unittest.main()
