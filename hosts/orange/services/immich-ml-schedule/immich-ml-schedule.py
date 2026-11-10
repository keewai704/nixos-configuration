import http.client
import json
import os
import sys
import time
import urllib.request
from pathlib import Path

API_URL = os.environ["IMMICH_API_URL"].rstrip("/")
WAKE_URL = os.environ["CITRUS_WAKE_URL"]
ALIVE_URL = os.environ["CITRUS_ALIVE_URL"]
SUSPEND_URL = os.environ["CITRUS_SUSPEND_URL"]
API_KEY = (Path(os.environ["CREDENTIALS_DIRECTORY"]) / "api-key").read_text().strip()

INFERENCE_QUEUES = ["smartSearch", "ocr", "faceDetection"]
QUEUED_JOBS = [*INFERENCE_QUEUES, "duplicateDetection"]
WATCHED_QUEUES = {*QUEUED_JOBS, "facialRecognition"}
BUSY_STATES = ["active", "waiting", "delayed", "paused"]
FAILURES = (OSError, http.client.HTTPException)

WAKE_TIMEOUT = 240
WAKE_RESEND = 10
ALIVE_TIMEOUT = 3
API_READY_TIMEOUT = 300
IDLE_POLL = 10
IDLE_CHECKS = 3


def request(url, method="GET", body=None, headers=None, timeout=60):
    data = None if body is None else json.dumps(body).encode()
    all_headers = {"Content-Type": "application/json", **(headers or {})}
    call = urllib.request.Request(url, data, all_headers, method=method)
    with urllib.request.urlopen(call, timeout=timeout) as response:
        return response.status, response.read()


def api(method, path, body=None):
    return request(f"{API_URL}{path}", method, body, {"x-api-key": API_KEY})[1]


def command(name, verb):
    api("PUT", f"/jobs/{name}", {"command": verb, "force": False})


def pause():
    for name in INFERENCE_QUEUES:
        command(name, "pause")


def citrus_alive():
    try:
        return request(ALIVE_URL, timeout=ALIVE_TIMEOUT)[0] == 204
    except FAILURES:
        return False


def wake_citrus():
    deadline = time.monotonic() + WAKE_TIMEOUT
    next_packet = 0.0
    while time.monotonic() < deadline:
        if citrus_alive():
            return True
        if time.monotonic() >= next_packet:
            request(WAKE_URL, "POST", {})
            next_packet = time.monotonic() + WAKE_RESEND
        time.sleep(2)
    return False


def queues_idle():
    for queue in json.loads(api("GET", "/queues")):
        if queue["name"] in WATCHED_QUEUES and any(queue["statistics"][state] for state in BUSY_STATES):
            return False
    return True


def wait_until_idle():
    idle = 0
    while idle < IDLE_CHECKS:
        time.sleep(IDLE_POLL)
        idle = idle + 1 if queues_idle() else 0


def run():
    woke = not citrus_alive()
    if woke:
        print("citrus is not responding, sending Wake-on-LAN", flush=True)
        if not wake_citrus():
            sys.exit("citrus did not wake")
    try:
        for name in INFERENCE_QUEUES:
            command(name, "resume")
        for name in QUEUED_JOBS:
            command(name, "start")
        wait_until_idle()
    finally:
        try:
            pause()
        finally:
            if woke:
                print("suspending citrus", flush=True)
                request(SUSPEND_URL, "POST", {})


def pause_when_ready():
    deadline = time.monotonic() + API_READY_TIMEOUT
    while True:
        try:
            pause()
            return
        except FAILURES:
            if time.monotonic() >= deadline:
                raise
            time.sleep(5)


{"run": run, "pause": pause_when_ready}[sys.argv[1]]()
