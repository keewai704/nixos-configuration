import argparse
import bisect
import csv
import hashlib
import json
import logging
import os
import stat
import statistics
import subprocess
import time
from pathlib import Path


class RecordingBusy(Exception):
    pass


def identity(path):
    item = path.stat()
    return item.st_dev, item.st_ino, item.st_size, item.st_mtime_ns


def writable(path):
    target = path.stat()
    for process in Path('/proc').iterdir():
        if not process.name.isdigit():
            continue
        try:
            if (process / 'comm').read_text().strip() != 'EpgDataCap_Bon':
                continue
            for fd in (process / 'fd').iterdir():
                try:
                    item = fd.stat()
                    if (item.st_dev, item.st_ino) != (target.st_dev, target.st_ino):
                        continue
                    fields = dict(line.split(':', 1) for line in
                                  (process / 'fdinfo' / fd.name).read_text().splitlines())
                    if int(fields['flags'].strip(), 8) & os.O_ACCMODE:
                        return True
                except FileNotFoundError:
                    continue
        except (FileNotFoundError, ProcessLookupError):
            continue
        except PermissionError:
            return True
    return False


def probe(binary, path):
    result = subprocess.run([binary, '-v', 'error', '-show_programs', '-show_format',
                             '-of', 'json', str(path)], capture_output=True, check=True)
    return json.loads(result.stdout)


def program(info, sid):
    matches = [item for item in info['programs'] if int(item['program_id']) == sid]
    if len(matches) != 1:
        raise ValueError(f'Expected one program for service {sid}')
    selected = matches[0]
    videos = [item for item in selected['streams'] if item.get('codec_type') == 'video']
    if len(videos) != 1:
        raise ValueError('Expected one video stream in the selected service')
    return selected, videos[0]


def packet_digest(path, video):
    digests = {}
    pcr = {}
    with path.open('rb') as stream:
        while chunk := stream.read(188 * 4096):
            if len(chunk) % 188:
                raise ValueError('Incomplete transport packet')
            for offset in range(0, len(chunk), 188):
                packet = chunk[offset:offset + 188]
                if packet[0] != 0x47:
                    raise ValueError('Transport packet synchronization lost')
                pid = ((packet[1] & 0x1f) << 8) | packet[2]
                if pid not in digests:
                    digests[pid] = [0, hashlib.sha256()]
                digests[pid][0] += 1
                if pid != video and pid != 0x1fff:
                    digests[pid][1].update(packet)
                if packet[3] & 0x20 and packet[4] >= 7 and packet[5] & 0x10:
                    base = (packet[6] << 25) | (packet[7] << 17) | (packet[8] << 9)
                    base |= (packet[9] << 1) | (packet[10] >> 7)
                    if pid not in pcr:
                        pcr[pid] = [0, hashlib.sha256()]
                    pcr[pid][0] += 1
                    pcr[pid][1].update(base.to_bytes(8, 'big'))
    finish = lambda values: {pid: (count, digest.hexdigest())
                             for pid, (count, digest) in values.items()}
    return finish(digests), finish(pcr)


def verify_packets(before, after, old_program, old_video, new_program, new_video):
    video_pid = int(old_video['id'], 0)
    if int(new_video['id'], 0) != video_pid:
        raise ValueError('Video PID changed')
    if old_program['pmt_pid'] != new_program['pmt_pid']:
        raise ValueError('PMT PID changed')
    old_packets, old_pcr = before
    new_packets, new_pcr = after
    exceptions = {video_pid, int(old_program['pmt_pid']), 0x1fff}
    preserved = {pid: value for pid, value in old_packets.items() if pid not in exceptions}
    for pid, expected in preserved.items():
        if new_packets.get(pid) != expected:
            raise ValueError(f'Non-video PID {pid:#x} was changed or lost')
    added = set(new_packets) - set(old_packets) - {0x1fff}
    old_clock = int(old_program['pcr_pid'])
    new_clock = int(new_program['pcr_pid'])
    if old_clock == video_pid:
        if added != {new_clock} or new_pcr.get(new_clock) != old_pcr.get(old_clock):
            raise ValueError('Relocated PCR timeline was changed')
    elif new_clock != old_clock or added:
        raise ValueError('Unexpected PID or PCR change')
    return {str(pid): {'packets': value[0], 'sha256': value[1]}
            for pid, value in preserved.items()}


def psi_sections(path, pid):
    buffer = bytearray()
    with path.open('rb') as stream:
        while chunk := stream.read(188 * 4096):
            for offset in range(0, len(chunk), 188):
                packet = chunk[offset:offset + 188]
                if len(packet) != 188 or packet[0] != 0x47:
                    raise ValueError('Invalid transport packet while reading PMT')
                if ((packet[1] & 0x1f) << 8) | packet[2] != pid or not packet[3] & 0x10:
                    continue
                start = 5 + packet[4] if packet[3] & 0x20 else 4
                payload = packet[start:]
                if not payload:
                    continue
                if packet[1] & 0x40:
                    pointer = payload[0]
                    if pointer >= len(payload):
                        raise ValueError('Invalid PSI pointer')
                    if buffer:
                        buffer.extend(payload[1:1 + pointer])
                        length = 3 + ((buffer[1] & 15) << 8) + buffer[2]
                        if len(buffer) < length:
                            raise ValueError('Incomplete PMT section')
                        yield bytes(buffer[:length])
                    buffer = bytearray(payload[1 + pointer:])
                elif buffer:
                    buffer.extend(payload)
                while len(buffer) >= 3:
                    if buffer[0] == 0xff:
                        buffer.clear()
                        break
                    length = 3 + ((buffer[1] & 15) << 8) + buffer[2]
                    if length > 4096:
                        raise ValueError('Oversized PSI section')
                    if len(buffer) < length:
                        break
                    yield bytes(buffer[:length])
                    del buffer[:length]


def pmt_bindings(path, pid, video_pid, codec):
    tables = set()
    for section in psi_sections(path, pid):
        if len(section) < 16 or section[0] != 2:
            raise ValueError('Invalid PMT')
        crc = 0xffffffff
        for byte in section:
            crc ^= byte << 24
            for _ in range(8):
                crc = ((crc << 1) ^ (0x04c11db7 if crc & 0x80000000 else 0)) & 0xffffffff
        if crc:
            raise ValueError('Invalid PMT CRC')
        start = 12 + ((section[10] & 15) << 8) + section[11]
        descriptors = section[12:start]
        others = []
        found = False
        while start < len(section) - 4:
            if start + 5 > len(section) - 4:
                raise ValueError('Truncated PMT stream binding')
            stream_pid = ((section[start + 1] & 31) << 8) | section[start + 2]
            end = start + 5 + ((section[start + 3] & 15) << 8) + section[start + 4]
            if end > len(section) - 4:
                raise ValueError('Truncated PMT descriptors')
            if stream_pid == video_pid:
                if section[start] != codec:
                    raise ValueError('Incorrect video codec in PMT')
                found = True
            else:
                others.append(bytes(section[start:end]))
            start = end
        if not found:
            raise ValueError('Video binding missing from PMT')
        tables.add((bytes(section[3:5]), section[5] & 1, section[6], section[7],
                    descriptors, tuple(others)))
    if not tables:
        raise ValueError('No PMT sections found')
    return tables


def video_timeline(ffprobe, path, video, strict):
    command = [ffprobe, '-v', 'error', '-select_streams', str(video['index']),
               '-show_packets', '-show_entries', 'packet=pts,dts,duration,flags:packet_side_data=',
               '-of', 'csv=p=0', str(path)]
    points = []
    first_keyframe = None
    previous_dts = None
    last_raw = None
    wrap = 1 << 33
    delta = lambda a, b: (a - b + wrap // 2) % wrap - wrap // 2
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          text=True) as process:
        for row in csv.reader(process.stdout):
            if not row or row[0] == 'N/A':
                continue
            pts = int(row[0])
            if len(row) > 1 and row[1] != 'N/A':
                raw = int(row[1])
                if previous_dts is None:
                    dts = raw
                else:
                    step = delta(raw, last_raw)
                    if strict and step <= 0:
                        raise ValueError('Video DTS is not increasing')
                    dts = previous_dts + step
                pts = dts + delta(pts, raw)
                previous_dts, last_raw = dts, raw
            elif points:
                pts = points[-1] + delta(pts, points[-1])
            points.append(pts)
            if len(row) > 3 and 'K' in row[3] and first_keyframe is None:
                first_keyframe = pts
        if process.wait():
            raise ValueError('Video timestamp analysis failed')
    if len(points) < 3 or first_keyframe is None or strict and previous_dts is None:
        raise ValueError('Insufficient video timestamps')
    return sorted(set(points)), first_keyframe


def verify_timeline(before, after, bob):
    before, first_keyframe = before
    after, _ = after
    wrap = 1 << 33
    shift = round((before[0] - after[0]) / wrap) * wrap
    after = [point + shift for point in after]
    step = statistics.median(b - a for a, b in zip(before, before[1:]) if b > a)
    if step <= 0 or step > 90000:
        raise ValueError('Invalid source frame interval')
    expected = [point for point in before if point >= first_keyframe]
    tolerance = max(4, step / 10)
    if abs(expected[-1] - after[-1]) > step / (2 if bob else 1):
        raise ValueError('Output video ends before or after the original')
    for point in expected:
        index = bisect.bisect_left(after, point)
        neighbors = after[max(0, index - 1):index + 1]
        if not neighbors or min(abs(value - point) for value in neighbors) > tolerance:
            raise ValueError('Output video timestamp coverage differs from the original')


def decode_video(ffmpeg, path, index, log):
    subprocess.run([ffmpeg, '-nostdin', '-hide_banner', '-v', 'error', '-threads', '2',
                    '-xerror', '-err_detect', 'explode', '-i', str(path),
                    '-map', f'0:{index}', '-an', '-sn', '-dn', '-f', 'null', '-'],
                   stdout=subprocess.DEVNULL, stderr=log, check=True)


def convert(job, args):
    fields = job.read_bytes().split(b'\0')
    if len(fields) != 4 or fields[-1] or not job.stem.isdecimal():
        raise ValueError('Invalid recording queue entry')
    source = Path(os.fsdecode(fields[0])).resolve(strict=True)
    sid, rec_id = int(fields[1]), int(fields[2])
    if rec_id != int(job.stem):
        raise ValueError('Recording ID does not match its queue entry')
    if not source.is_relative_to(args.recordings.resolve()) or source.suffix.lower() != '.ts':
        raise ValueError('Recording is outside the managed TS directory')
    original = source.stat()
    if not stat.S_ISREG(original.st_mode):
        raise ValueError('Recording is not a regular file')
    if time.time() - original.st_mtime < 3 or writable(source):
        raise RecordingBusy()
    backup = source.with_name(f'.{source.name}.{job.stem}.original')
    if backup.exists():
        if backup.samefile(source):
            backup.unlink()
        else:
            os.replace(backup, source)
        original = source.stat()
    before = identity(source)
    old_info = probe(args.ffprobe, source)
    old_program, old_video = program(old_info, sid)
    if old_video['codec_name'] == 'hevc':
        logging.info('Recording %s is already HEVC', rec_id)
        return
    if old_video['codec_name'] != 'mpeg2video':
        raise ValueError('Only MPEG-2 broadcast video is eligible')
    original_packets = packet_digest(source, int(old_video['id'], 0))
    old_bindings = pmt_bindings(source, int(old_program['pmt_pid']), int(old_video['id'], 0), 2)
    old_timeline = video_timeline(args.ffprobe, source, old_video, False)
    partial = source.with_name(f'.{source.name}.{job.stem}.hevc.partial')
    partial.unlink(missing_ok=True)
    interlace = []
    field_order = old_video.get('field_order')
    if field_order in ('tt', 'tb', 'bb', 'bt'):
        interlace = ['--tff' if field_order in ('tt', 'bt') else '--bff',
                     '--vpp-deinterlace', 'bob']
    command = [args.tsreplace, '-i', str(source), '-o', str(partial), '--service', str(sid),
               '--preserve-other-services', '--no-remove-typed', '--copy-filets',
               '-e', args.encoder, '--avhw', '-i', '-', '--input-format', 'mpegts',
               *interlace, '-c', 'hevc', '--icq', '23', '--gop-len', '120',
               '--colormatrix', 'auto', '--colorprim', 'auto', '--transfer', 'auto',
               '--colorrange', 'auto',
               '--quality', 'balanced', '--avsync', 'vfr', '--disable-opencl',
               '--output-format', 'mpegts', '-o', '-']
    try:
        log_path = args.logs / f'{rec_id}.log'
        with log_path.open('ab', buffering=0) as log:
            subprocess.run(command, stdout=log, stderr=log, check=True)
            new_info = probe(args.ffprobe, partial)
            new_program, new_video = program(new_info, sid)
            if new_video['codec_name'] != 'hevc':
                raise ValueError('Replacement video is not HEVC')
            for dimension in ('width', 'height'):
                if new_video[dimension] != old_video[dimension]:
                    raise ValueError(f'Video {dimension} was changed')
            for key in ('sample_aspect_ratio', 'color_range', 'color_space',
                        'color_transfer', 'color_primaries'):
                if key in old_video and new_video.get(key) != old_video[key]:
                    raise ValueError(f'Video {key} was changed')
            for timestamp in ('start_time', 'duration'):
                if timestamp not in old_video or timestamp not in new_video:
                    raise ValueError(f'Missing video {timestamp}')
                if abs(float(old_video[timestamp]) - float(new_video[timestamp])) > 2:
                    raise ValueError(f'Video {timestamp} changed by more than two seconds')
            preserved = verify_packets(original_packets,
                                       packet_digest(partial, int(new_video['id'], 0)),
                                       old_program, old_video, new_program, new_video)
            if old_bindings != pmt_bindings(partial, int(new_program['pmt_pid']),
                                            int(new_video['id'], 0), 0x24):
                raise ValueError('Non-video PMT descriptors or bindings changed')
            verify_timeline(old_timeline, video_timeline(args.ffprobe, partial, new_video, True),
                            bool(interlace))
            decode_video(args.ffmpeg, partial, new_video['index'], log)
        if identity(source) != before or writable(source):
            raise RecordingBusy()
        os.chmod(partial, stat.S_IMODE(original.st_mode))
        os.utime(partial, ns=(original.st_atime_ns, original.st_mtime_ns))
        with partial.open('rb') as output:
            os.fsync(output.fileno())
        report = {'recording_id': rec_id, 'service_id': sid, 'input_bytes': original.st_size,
                  'output_bytes': partial.stat().st_size, 'codec': 'hevc',
                  'preserved_pids': preserved, 'full_video_decode': True}
        os.link(source, backup)
        try:
            os.replace(partial, source)
            folder_fd = os.open(source.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(folder_fd)
            finally:
                os.close(folder_fd)
            report_path = args.queue.parent / 'completed' / f'{rec_id}.json'
            with report_path.open('w') as report_file:
                json.dump(report, report_file)
                report_file.flush()
                os.fsync(report_file.fileno())
        except BaseException:
            if backup.exists():
                os.replace(backup, source)
            raise
        backup.unlink()
        logging.info('Recording %s verified and replaced: %d -> %d bytes, %d preserved PIDs',
                     rec_id, original.st_size, source.stat().st_size, len(preserved))
    finally:
        partial.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser()
    for name in ('queue', 'recordings', 'logs'):
        parser.add_argument('--' + name, type=Path, required=True)
    for name in ('encoder', 'ffmpeg', 'ffprobe', 'tsreplace'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--once', action='store_true')
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
    for directory in [args.queue, args.queue.parent / 'failed', args.queue.parent / 'completed', args.logs]:
        directory.mkdir(parents=True, exist_ok=True)
    while True:
        for job in sorted(args.queue.glob('*.job'), key=lambda path: path.stat().st_mtime):
            try:
                convert(job, args)
                job.unlink()
            except RecordingBusy:
                continue
            except Exception:
                logging.exception('Recording job %s failed; no unverified output published', job.stem)
                os.replace(job, args.queue.parent / 'failed' / job.name)
        if args.once:
            return
        time.sleep(1)


if __name__ == '__main__':
    main()
