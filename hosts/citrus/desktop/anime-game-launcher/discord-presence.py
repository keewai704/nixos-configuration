import json
import os
import socket
import struct
import time
import uuid

CLIENT_ID = "762434991303950386"
EXECUTABLE = "genshinimpact.exe"


def game_start():
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            with open(f"/proc/{pid}/comm") as handle:
                comm = handle.read().strip().lower()
            with open(f"/proc/{pid}/cmdline", "rb") as handle:
                argv0 = handle.read().split(b"\0", 1)[0].decode(errors="replace")
            name = argv0.replace("\\", "/").rsplit("/", 1)[-1].lower()
            if EXECUTABLE[:15] != comm and EXECUTABLE != name:
                continue
            with open(f"/proc/{pid}/stat") as handle:
                ticks = int(handle.read().rsplit(")", 1)[1].split()[19])
        except OSError:
            continue
        with open("/proc/stat") as handle:
            boot = next(int(line.split()[1]) for line in handle if line.startswith("btime "))
        return boot + ticks // os.sysconf("SC_CLK_TCK")
    return None


def send(connection, op, payload):
    data = json.dumps(payload).encode()
    connection.sendall(struct.pack("<II", op, len(data)) + data)
    op, length = struct.unpack("<II", receive(connection, 8))
    reply = json.loads(receive(connection, length))
    if op != 1 or reply.get("evt") == "ERROR":
        raise OSError(f"Discord rejected the request: {reply}")


def receive(connection, length):
    data = b""
    while len(data) < length:
        chunk = connection.recv(length - len(data))
        if not chunk:
            raise OSError("Discord closed the connection")
        data += chunk
    return data


def connect(start):
    runtime = os.environ["XDG_RUNTIME_DIR"]
    for index in range(10):
        connection = socket.socket(socket.AF_UNIX)
        connection.settimeout(5)
        try:
            connection.connect(f"{runtime}/discord-ipc-{index}")
            send(connection, 0, {"v": 1, "client_id": CLIENT_ID})
            send(connection, 1, {
                "cmd": "SET_ACTIVITY",
                "args": {"pid": os.getpid(), "activity": {"timestamps": {"start": start * 1000}}},
                "nonce": str(uuid.uuid4()),
            })
            return connection
        except OSError as error:
            connection.close()
            last = error
    print(f"Discord is unavailable: {last}", flush=True)
    return None


connection = None
while True:
    start = game_start()
    if start and connection is None:
        connection = connect(start)
    elif connection:
        try:
            connection.setblocking(False)
            if not start or connection.recv(65536) == b"":
                raise OSError
        except BlockingIOError:
            pass
        except OSError:
            connection.close()
            connection = None
        if connection:
            connection.settimeout(5)
    time.sleep(5)
