import array
import ctypes
import errno
import json
import shutil
import socket
import struct
import sys
import tempfile
import threading
import time
from contextlib import ExitStack
from pathlib import Path


class BonStruct(ctypes.Structure):
    _fields_ = [('context', ctypes.c_void_p), ('end', ctypes.c_void_p)] + [
        (f'f{index}', ctypes.c_void_p) for index in range(17)
    ]


signatures = [
    (ctypes.c_int, []),
    (None, []),
    (ctypes.c_int, [ctypes.c_uint8]),
    (ctypes.c_float, []),
    (ctypes.c_uint32, [ctypes.c_uint32]),
    (ctypes.c_uint32, []),
    (ctypes.c_int, [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(ctypes.c_uint32)]),
    (ctypes.c_int, [ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(ctypes.c_uint32)]),
    (None, []),
    (None, []),
    (ctypes.c_void_p, []),
    (ctypes.c_int, []),
    (ctypes.c_void_p, [ctypes.c_uint32]),
    (ctypes.c_void_p, [ctypes.c_uint32, ctypes.c_uint32]),
    (ctypes.c_int, [ctypes.c_uint32, ctypes.c_uint32]),
    (ctypes.c_uint32, []),
    (ctypes.c_uint32, []),
]


class Driver:
    def __init__(self, path):
        self.library = ctypes.CDLL(str(path))
        self.library.CreateBonStruct.restype = ctypes.POINTER(BonStruct)
        pointer = self.library.CreateBonStruct()
        assert pointer, 'CreateBonStruct failed'
        self.api = pointer.contents
        assert self.api.end - ctypes.addressof(self.api) >= ctypes.sizeof(BonStruct)

    def call(self, index, *arguments):
        result, parameters = signatures[index]
        function = ctypes.CFUNCTYPE(result, ctypes.c_void_p, *parameters)(getattr(self.api, f'f{index}'))
        return function(self.api.context, *arguments)

    def text(self, index, *arguments):
        pointer = self.call(index, *arguments)
        if not pointer:
            return None
        characters = ctypes.cast(pointer, ctypes.POINTER(ctypes.c_uint16))
        data = bytearray()
        for offset in range(1024):
            if not characters[offset]:
                return data.decode('utf-16-le')
            data.extend(struct.pack('<H', characters[offset]))
        raise AssertionError('unterminated BonDriver name')

    def data(self, copy=False):
        size, remain = ctypes.c_uint32(), ctypes.c_uint32()
        if copy:
            buffer = ctypes.create_string_buffer(188 * 256)
            result = self.call(6, buffer, ctypes.byref(size), ctypes.byref(remain))
            data = buffer.raw[:size.value]
        else:
            pointer = ctypes.c_void_p()
            result = self.call(7, ctypes.byref(pointer), ctypes.byref(size), ctypes.byref(remain))
            data = ctypes.string_at(pointer, size.value) if pointer.value else b''
        return result, data, remain.value

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.call(9)


class Receiver:
    def __init__(self, path):
        self.path = path
        self.lock = threading.Lock()
        self.owner = None
        self.output = None
        self.connections = []
        self.workers = []
        self.stopping = threading.Event()
        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        self.listener.bind(str(path))
        self.listener.listen()
        self.listener.settimeout(0.1)
        self.thread = threading.Thread(target=self.accept)
        self.thread.start()

    def accept(self):
        while not self.stopping.is_set():
            try:
                connection, _ = self.listener.accept()
            except TimeoutError:
                continue
            except OSError:
                break
            with self.lock:
                if self.owner:
                    connection.send(struct.pack('iIii', -errno.EBUSY, 0, 0, 0))
                    connection.close()
                    continue
                self.owner = connection
                self.connections.append(connection)
            connection.send(bytes(16))
            worker = threading.Thread(target=self.handle, args=(connection,))
            self.workers.append(worker)
            worker.start()

    def handle(self, connection):
        try:
            while request := connection.recv(64):
                version, command, channel, tsid = struct.unpack('IIII', request)
                assert version == 1
                if command == 1:
                    self.stop_stream()
                    if channel == 15:
                        connection.send(struct.pack('iIii', -errno.EAGAIN, 0, 0, 0))
                        continue
                    output, reader = socket.socketpair()
                    output.settimeout(5)
                    with self.lock:
                        self.output = output
                    connection.sendmsg([bytes(16)], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array('i', [reader.fileno()]))])
                    reader.close()
                elif command == 2:
                    connection.send(struct.pack('iIii', 0, 1, 3125, -42000))
                elif command == 3:
                    self.stop_stream()
                    connection.send(bytes(16))
                else:
                    raise AssertionError('unexpected receiver command')
        except (ConnectionError, OSError):
            pass
        finally:
            self.stop_stream()
            connection.close()
            with self.lock:
                if self.owner is connection:
                    self.owner = None

    def stop_stream(self):
        with self.lock:
            output, self.output = self.output, None
        if output:
            try:
                output.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            output.close()

    def emit(self, payload):
        with self.lock:
            output = self.output
        assert output, 'no tuned stream'
        output.sendall(payload)

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.stopping.set()
        self.listener.close()
        self.stop_stream()
        for connection in self.connections:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        self.thread.join(2)
        for worker in self.workers:
            worker.join(2)
            assert not worker.is_alive()


def until(predicate, timeout=3):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.01)
    raise AssertionError('condition did not become true')


def check_packets(data):
    assert data and len(data) % 188 == 0
    assert all(data[offset] == 0x47 for offset in range(0, len(data), 188))


def test(library):
    with tempfile.TemporaryDirectory() as temporary, ExitStack() as stack:
        root = Path(temporary)
        paths, receivers = [], []
        channels = root / 'channels.tsv'
        channels.write_text('14\t32725\t読売テレビ\n24\t32112\tNHK総合大阪\n15\t32723\tABCテレビ\n', encoding='utf-8')
        for index in range(2):
            path = root / f'BonDriver_Torne{index}.so'
            shutil.copyfile(library, path)
            socket_path = root / f'{index}.sock'
            Path(f'{path}.ini').write_text(f'[Torne]\nSocket={socket_path}\nName=torne {index}\nChannels={channels}\n', encoding='utf-8')
            paths.append(path)
            receivers.append(stack.enter_context(Receiver(socket_path)))
        first = stack.enter_context(Driver(paths[0]))
        second = stack.enter_context(Driver(paths[1]))
        duplicate = stack.enter_context(Driver(paths[0]))
        assert first.text(10) == 'torne 0'
        assert second.text(10) == 'torne 1'
        assert first.text(12, 0) == '地上デジタル'
        assert first.text(12, 1) is None
        assert first.text(13, 0, 0) == '読売テレビ'
        assert first.text(13, 0, 1) == 'NHK総合大阪'
        assert first.text(13, 0, 3) is None
        assert not first.call(11)
        assert first.call(15) == 0xffffffff
        assert not first.call(14, 0, 0)
        assert first.call(0) and first.call(0)
        assert first.call(11)
        assert not duplicate.call(0)
        assert second.call(0)
        assert first.call(14, 0, 0)
        assert second.call(2, 24)
        assert second.call(16) == 1
        assert not second.call(2, 1)
        assert second.call(16) == 1
        assert first.call(15) == 0 and first.call(16) == 0
        assert not first.call(14, 1, 0)
        assert not first.call(14, 0, 99)
        assert first.call(16) == 0
        assert first.call(4, 20) == 0x102
        assert abs(first.call(3) - 31.25) < 0.01
        packet = bytes([0x47, 0x01, 0x00, 0x10]) + bytes(184)
        payload = packet * 11
        receivers[0].emit(payload[:17])
        receivers[0].emit(payload[17:513])
        receivers[0].emit(payload[513:])
        receivers[1].emit(packet * 7)
        received = bytearray()
        while len(received) < len(payload):
            assert first.call(4, 1000) == 0
            success, data, remain = first.data(copy=len(received) > 0)
            assert success
            check_packets(data)
            received.extend(data)
        assert received == payload
        assert second.call(4, 1000) == 0
        assert second.data(copy=True)[1] == packet * 7
        receivers[0].emit(packet * 4)
        until(lambda: first.call(5) > 0)
        first.call(8)
        assert first.call(5) == 0
        assert first.data() == (0, b'', 0)
        assert not first.call(14, 0, 2)
        assert first.call(16) == 0xffffffff
        assert first.call(14, 0, 1)
        assert first.call(16) == 1
        result = []
        waiting = threading.Thread(target=lambda: result.append(first.call(4, 0xffffffff)))
        waiting.start()
        time.sleep(0.02)
        first.call(1)
        waiting.join(2)
        assert not waiting.is_alive() and result == [0x80]
        assert not first.call(11)
        until(lambda: receivers[0].owner is None)
        assert duplicate.call(0)
        duplicate.call(1)
        until(lambda: receivers[0].owner is None)
        assert first.call(0) and first.call(14, 0, 0)
        for _ in range(3):
            first.call(1)
            until(lambda: receivers[0].owner is None)
            assert first.call(0) and first.call(14, 0, 0)
        def flood():
            try:
                receivers[0].emit(packet * (256 * 170))
            except OSError:
                pass

        filling = threading.Thread(target=flood)
        filling.start()
        until(lambda: first.call(5) == 128)
        first.call(1)
        filling.join(2)
        assert not filling.is_alive()
        until(lambda: receivers[0].owner is None)
        assert first.call(0) and first.call(14, 0, 0)
        receivers[0].stop_stream()
        assert first.call(4, 1000) == 0x80
        first.library.CreateBonDriver.restype = ctypes.c_void_p
        pointer = first.library.CreateBonDriver()
        assert pointer
        table = ctypes.cast(pointer, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
        ctypes.CFUNCTYPE(None, ctypes.c_void_p)(table[9])(pointer)
    print('BonDriver ABI, two-device isolation, busy handling, TS alignment, waits, purge, retune, failure and reopen: passed')


def live(arguments):
    assert len(arguments) % 3 == 0
    results, failures = [], []
    with ExitStack() as stack:
        drivers = []
        for offset in range(0, len(arguments), 3):
            path, channel, tsid = arguments[offset:offset + 3]
            driver = stack.enter_context(Driver(path))
            assert driver.call(0), f'cannot open {path}'
            assert driver.call(14, 0, int(channel)), f'cannot tune {path}'
            drivers.append((driver, int(tsid)))

        def collect(driver, expected):
            try:
                total, found = 0, set()
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    assert driver.call(4, 2000) == 0
                    success, data, _ = driver.data()
                    assert success
                    check_packets(data)
                    total += len(data)
                    for offset in range(0, len(data), 188):
                        packet = data[offset:offset + 188]
                        if packet[1] & 0x1f or packet[2] or not packet[1] & 0x40:
                            continue
                        start = 4 + (packet[4] + 1 if packet[3] & 0x20 else 0)
                        if start >= 188:
                            continue
                        start += 1 + packet[start]
                        if start + 5 < 188 and packet[start] == 0:
                            found.add(int.from_bytes(packet[start + 3:start + 5], 'big'))
                assert expected in found, (expected, found)
                signal = driver.call(3)
                assert signal > 0
                driver.call(8)
                results.append({'tuner': driver.text(10), 'bytes': total, 'PAT': sorted(found), 'CNR_dB': signal})
            except BaseException as error:
                failures.append(error)

        workers = [threading.Thread(target=collect, args=pair) for pair in drivers]
        for worker in workers:
            worker.start()
        for worker in workers:
            worker.join(15)
            assert not worker.is_alive()
        if failures:
            raise failures[0]
    print(json.dumps(results, ensure_ascii=False))


if __name__ == '__main__':
    if sys.argv[1] == '--live':
        live(sys.argv[2:])
    else:
        test(Path(sys.argv[1]))
