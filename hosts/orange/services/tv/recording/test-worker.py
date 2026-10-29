import errno
import importlib.util
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

source = Path(sys.argv.pop(1))
spec = importlib.util.spec_from_file_location('recording_encode', source)
encoder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(encoder)
PID = 496


def pmt(size=21):
    descriptors = size - 21
    if descriptors and descriptors < 2:
        raise ValueError('Descriptor requires a tag and length')
    data = bytearray([2, 0xb0, size - 3, 0xa0, 0, 0xc1, 0, 0, 0xe1, 0xff, 0xf0, 0,
                      0x24, 0xe1, 0, 0xf0, descriptors])
    if descriptors:
        data.extend([0x80, descriptors - 2])
        data.extend(bytes(descriptors - 2))
    return with_crc(data)


def with_crc(data):
    crc = 0xffffffff
    for byte in data:
        crc ^= byte << 24
        for _ in range(8):
            crc = ((crc << 1) ^ (0x04c11db7 if crc & 0x80000000 else 0)) & 0xffffffff
    return bytes(data) + crc.to_bytes(4, 'big')


def packet(payload, start=True, counter=0, exact=False):
    header = bytes([0x47, (0x40 if start else 0) | (PID >> 8), PID & 255,
                    (0x30 if exact else 0x10) | counter])
    if exact:
        length = 183 - len(payload)
        return header + bytes([length, 0]) + bytes([255]) * (length - 1) + payload
    return header + payload + bytes([255]) * (184 - len(payload))


class PSISections(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'sample.ts'

    def scan(self, packets):
        self.path.write_bytes(b''.join(packets))
        return list(encoder.psi_sections(self.path, PID))

    def test_one_or_two_stuffing_bytes_before_next_section(self):
        for size in (181, 182, 183):
            with self.subTest(size=size):
                section = pmt(size)
                self.assertEqual(self.scan([packet(b'\0' + section),
                                            packet(b'\0' + section, counter=1)]),
                                 [section, section])
                self.assertEqual(len(encoder.pmt_bindings(self.path, PID, 256, 0x24)), 1)

    def test_header_split_across_continuation_packets(self):
        section = pmt()
        for length in (1, 2):
            with self.subTest(length=length):
                self.assertEqual(self.scan([packet(b'\0' + section[:length], exact=True),
                                            packet(section[length:], start=False, counter=1)]),
                                 [section])

    def test_pointer_finishes_previous_header_and_starts_next_section(self):
        section = pmt()
        for length in (1, 2):
            with self.subTest(length=length):
                rest = section[length:]
                self.assertEqual(self.scan([packet(b'\0' + section[:length], exact=True),
                                            packet(bytes([len(rest)]) + rest + section, counter=1)]),
                                 [section, section])

    def test_incomplete_header_before_new_section_is_rejected(self):
        for length in (1, 2):
            with self.subTest(length=length):
                with self.assertRaisesRegex(ValueError, 'Incomplete PMT section'):
                    self.scan([packet(b'\0' + pmt()[:length], exact=True),
                               packet(b'\0' + pmt(), counter=1)])

    def test_bad_crc_is_rejected(self):
        section = bytearray(pmt(181))
        section[-1] ^= 1
        self.scan([packet(b'\0' + section)])
        with self.assertRaisesRegex(ValueError, 'Invalid PMT CRC'):
            encoder.pmt_bindings(self.path, PID, 256, 0x24)

    def test_truncated_descriptors_are_rejected(self):
        section = bytearray(pmt(181)[:-4])
        section[16] += 1
        self.scan([packet(b'\0' + with_crc(section))])
        with self.assertRaisesRegex(ValueError, 'Truncated PMT descriptors'):
            encoder.pmt_bindings(self.path, PID, 256, 0x24)

    def test_oversized_section_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Oversized PSI section'):
            self.scan([packet(b'\0\x02\xbf\xff')])


class VideoTimeline(unittest.TestCase):
    def test_adaptive_24p_30p_60p_timing_keeps_source_coverage(self):
        source = [index * 3003 for index in range(21)]
        filtered = [0, 3003, 7508, 10511, 15015, 18018, 21021, 24024,
                    27027, 30030, 31532, 33033, 34535, 36036, 37538,
                    39039, 40541, 42042, 43544, 45045, 46547, 48048,
                    49550, 51051, 52553, 54054, 55556, 57057, 58559, 60060]
        encoder.verify_timeline((source, 0), (filtered, 0), True)

    def test_missing_middle_of_recording_is_rejected(self):
        source = [index * 3003 for index in range(20)]
        with self.assertRaisesRegex(ValueError, 'timestamp coverage'):
            encoder.verify_timeline((source, 0), (source[:3] + source[10:], 0), True)

    def test_amatsukaze_tail_pes_boundary_is_reported(self):
        source = [index * 3003 for index in range(20)]
        difference = encoder.verify_timeline((source, 0), (source[:-2], 0), True)
        self.assertAlmostEqual(difference, 66.733, places=3)

    def test_long_tail_trim_is_rejected(self):
        source = [index * 3003 for index in range(20)]
        with self.assertRaisesRegex(ValueError, 'ends before or after'):
            encoder.verify_timeline((source, 0), (source[:-5], 0), True)

    def test_tail_pes_reordering_keeps_the_final_frame(self):
        source = [index * 3003 for index in range(20)]
        encoder.verify_timeline((source, 0), (source[:-2] + source[-1:], 0), False)

    def test_source_pts_wrap_does_not_look_like_a_cut(self):
        source = [(1 << 33) + index * 3003 for index in range(5)]
        output = [index * 3003 for index in range(5)]
        encoder.verify_timeline((source, source[0]), (output, 0), False)

    def test_replacement_preserves_every_filtered_frame_with_offset(self):
        frames = [0, 3003, 7508, 10511, 15015]
        shifted = [value + 900000 for value in frames]
        encoder.verify_replacement_timeline((frames, 0), (shifted, shifted[0]))

    def test_replacement_cannot_drop_a_filtered_frame(self):
        frames = [0, 3003, 7508, 10511, 15015]
        with self.assertRaisesRegex(ValueError, 'frames were lost'):
            encoder.verify_replacement_timeline((frames, 0), (frames[:2] + frames[3:], 0))

    def test_replacement_cannot_flatten_variable_frame_times(self):
        frames = [0, 3003, 7508, 10511, 15015]
        flattened = [index * 3003 for index in range(5)]
        with self.assertRaisesRegex(ValueError, 'timing changed'):
            encoder.verify_replacement_timeline((frames, 0), (flattened, 0))


class RecordingWorkspace(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.work = self.root / 'work'
        self.work.mkdir()
        self.args = SimpleNamespace(
            queue=self.root / 'state/queue', recordings=self.root / 'recordings',
            logs=self.root / 'logs', logos=self.root / 'logos', work=self.work,
            filter=self.root / 'filter.avs', encoder='unused', muxer='unused',
            ffmpeg='unused', ffprobe='unused')
        self.args.logo_generator = self.tool('logo-generator', '''
            import sys
            from pathlib import Path
            logo = Path(sys.argv[sys.argv.index('-o') + 1])
            logo.with_name('station.genlogo.123.tmp.lgd').write_bytes(b'partial')
            logo.write_bytes(b'complete')
            logo.chmod(0o660)
        ''')
        self.args.amatsukaze = self.tool('amatsukaze', '''
            import json
            import os
            import sys
            from pathlib import Path
            for index, argument in enumerate(sys.argv):
                if argument == '--logo':
                    assert Path(sys.argv[index + 1]).read_bytes() == b'complete'
            source = Path(sys.argv[sys.argv.index('-i') + 1])
            if source.is_file() and source.read_bytes() == b'no matching logo':
                auto_detect = (sys.argv[sys.argv.index('--auto-logo-detect') + 1]
                               if '--auto-logo-detect' in sys.argv else '1')
                if auto_detect != '0':
                    logo = Path(sys.argv[sys.argv.index('--logo') + 1])
                    (logo.parent / 'SID101-auto.lgd').write_bytes(b'partial')
            output = Path(sys.argv[sys.argv.index('-o') + 1])
            output.write_bytes(b'encoded fixture')
            result = Path(sys.argv[sys.argv.index('-j') + 1])
            result.write_text(json.dumps({'cmanalyze': True, 'outfiles': [{'path': str(output)}]}))
            Path(os.environ['TV_RECORDING_REPLACEMENT_REPORT']).write_text(
                json.dumps({'timeline': [[0, 3003, 6006], 0]}))
        ''')
        self.cache = self.args.logos / '101-64x64'
        self.cache.mkdir(parents=True)

    def tool(self, name, body):
        path = self.root / name
        path.write_text(f'#!{sys.executable}\n' + textwrap.dedent(body))
        path.chmod(0o755)
        return str(path)

    def analyze(self):
        with (self.root / 'analysis.log').open('ab') as log:
            return encoder.analyze_recording(
                self.root / 'source.ts', 101,
                {'width': 64, 'height': 64, 'field_order': 'progressive'},
                self.args, self.work, log)

    def test_interrupted_logo_is_not_reused_as_a_completed_cache(self):
        (self.cache / 'station.genlogo.99.tmp.lgd').write_bytes(b'partial')
        self.analyze()
        self.assertEqual((self.cache / 'station.lgd').read_bytes(), b'complete')
        self.assertTrue((self.work / 'station.genlogo.123.tmp.lgd').exists())
        self.assertFalse((self.cache / 'station.genlogo.123.tmp.lgd').exists())

    def test_completed_custom_logo_is_reused_without_temporary_logos(self):
        (self.cache / 'custom.lgd').write_bytes(b'complete')
        (self.cache / 'station.genlogo.99.tmp.lgd').write_bytes(b'partial')
        self.args.logo_generator = self.tool('unexpected-generator', 'raise SystemExit(1)')
        self.analyze()
        self.assertFalse((self.cache / 'station.lgd').exists())

    def test_unmatched_cached_logo_does_not_publish_partial_redetection(self):
        cached = self.cache / 'custom.lgd'
        cached.write_bytes(b'complete')
        (self.root / 'source.ts').write_bytes(b'no matching logo')
        self.args.logo_generator = self.tool('unexpected-generator', 'raise SystemExit(1)')
        output, _, _, _, result = self.analyze()
        self.assertTrue(output.is_file())
        self.assertTrue(result['cmanalyze'])
        self.assertEqual(list(self.cache.iterdir()), [cached])

    def test_generated_logo_is_published_across_mount_boundaries(self):
        replace = Path.replace

        def replace_within_mount(path, target):
            if path.is_relative_to(self.work) and Path(target).is_relative_to(self.args.logos):
                raise OSError(errno.EXDEV, 'Separate mount points')
            return replace(path, target)

        with patch.object(Path, 'replace', replace_within_mount):
            self.analyze()
        cached = self.cache / 'station.lgd'
        self.assertEqual(cached.read_bytes(), b'complete')
        self.assertEqual(cached.stat().st_mode & 0o777, 0o660)
        self.assertEqual(list(self.cache.iterdir()), [cached])

    def test_cache_copy_failure_does_not_publish_a_partial_logo(self):
        def fail_copy(source, destination):
            destination.write(b'partial')
            raise OSError(errno.ENOSPC, 'No space left')

        with patch.object(encoder.shutil, 'copyfileobj', fail_copy):
            with self.assertRaises(OSError):
                self.analyze()
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_cache_sync_failure_does_not_publish_a_logo(self):
        with patch.object(encoder.os, 'fsync', side_effect=OSError(errno.EIO, 'Sync failed')):
            with self.assertRaises(OSError):
                self.analyze()
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_failed_generation_does_not_publish_an_incomplete_logo(self):
        self.args.logo_generator = self.tool('failing-generator', '''
            import sys
            from pathlib import Path
            logo = Path(sys.argv[sys.argv.index('-o') + 1])
            logo.with_name('station.genlogo.123.tmp.lgd').write_bytes(b'partial')
            raise SystemExit(1)
        ''')
        with self.assertRaises(subprocess.CalledProcessError):
            self.analyze()
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_empty_generated_logo_is_not_cached(self):
        self.args.logo_generator = self.tool('empty-generator', '''
            import sys
            from pathlib import Path
            Path(sys.argv[sys.argv.index('-o') + 1]).touch()
        ''')
        with self.assertRaisesRegex(ValueError, 'empty logo'):
            self.analyze()
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_startup_removes_abandoned_job_work_and_preserves_other_paths(self):
        abandoned = [Path(tempfile.mkdtemp(prefix=f'{number}-', dir=self.work))
                     for number in (1, 2)]
        for directory in abandoned:
            (directory / 'partial.ts').write_bytes(b'unfinished work')
        unrelated = self.work / 'notes'
        unrelated.mkdir()
        target = self.root / 'untouched'
        target.mkdir()
        (target / 'source.ts').write_bytes(b'original')
        link = self.work / '3-abcdefgh'
        link.symlink_to(target, target_is_directory=True)
        arguments = [str(source), '--once']
        for name in ('queue', 'recordings', 'logs', 'logos', 'work', 'filter',
                     'encoder', 'ffmpeg', 'ffprobe', 'amatsukaze', 'logo-generator', 'muxer'):
            arguments.extend(['--' + name, str(getattr(self.args, name.replace('-', '_')))])
        with patch.object(sys, 'argv', arguments):
            encoder.main()
        self.assertFalse(any(directory.exists() for directory in abandoned))
        self.assertTrue(unrelated.is_dir())
        self.assertTrue(link.is_symlink())
        self.assertEqual((target / 'source.ts').read_bytes(), b'original')


unittest.main()
