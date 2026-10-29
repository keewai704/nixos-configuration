import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

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


unittest.main()
