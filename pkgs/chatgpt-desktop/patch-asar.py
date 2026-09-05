#!/usr/bin/env python3
"""Patch the Linux Git watcher in the official ChatGPT ASAR bundle.

The bundled @parcel/watcher native module crashes during worker startup on
NixOS. The worker already contains an fs.watch implementation for the other
platforms, and Node's native recursive watcher is suitable for local Git
working trees here. Keep each replacement byte-for-byte the same size so the
ASAR offsets remain valid and update the corresponding integrity entries.
"""

import hashlib
import json
import mmap
import struct
import sys
from pathlib import Path


WATCHER_PATCHES = tuple(
    (needle, needle.replace(b"`linux`", b"`nixos`"))
    for needle in (
        b"startMetadataWatch:(t,n)=>t.isLocal?process.platform===`linux`&&n.recursive!==!1?"
        b"F9(n,{ignoredPaths:[]}):e.startFileWatch(n):t.startFileWatch(n)",
        b"startWorkingTreeWatch:(t,n,r)=>t.isLocal?process.platform===`linux`?"
        b"F9(n,{ignoredPaths:[E.posix.join(n.path,`.git`),...r]}):e.startFileWatch(n):"
        b"t.startFileWatch(n)",
    )
)


def worker_metadata(mapping: mmap.mmap) -> tuple[bytearray, dict, int, int]:
    """Read the ASAR header and return the worker's metadata and byte range."""

    header_size = struct.unpack_from("<I", mapping, 4)[0]
    header_start = 8
    header_end = header_start + header_size
    if header_end > len(mapping):
        raise RuntimeError("ASAR header extends past the archive")

    header = bytearray(mapping[header_start:header_end])
    json_size = struct.unpack_from("<I", header, 4)[0]
    json_start = 8
    json_end = json_start + json_size
    if json_end > len(header):
        raise RuntimeError("ASAR JSON header extends past the header")

    tree = json.loads(bytes(header[json_start:json_end]))
    worker = tree["files"][".vite"]["files"]["build"]["files"]["worker.js"]
    worker_start = header_end + int(worker["offset"])
    worker_end = worker_start + int(worker["size"])
    if worker_start < header_end or worker_end > len(mapping):
        raise RuntimeError("worker.js extends past the ASAR archive")
    return header, worker, worker_start, worker_end


def verify_worker_integrity(worker_bytes: bytes, worker: dict) -> str:
    """Check ASAR's whole-file and block SHA-256 integrity metadata."""

    integrity = worker.get("integrity")
    if not isinstance(integrity, dict) or integrity.get("algorithm") != "SHA256":
        raise RuntimeError("worker.js does not have SHA256 integrity metadata")

    block_size = int(integrity.get("blockSize", 0))
    blocks = integrity.get("blocks")
    if block_size <= 0 or not isinstance(blocks, list):
        raise RuntimeError("worker.js has incomplete integrity metadata")

    whole_hash = hashlib.sha256(worker_bytes).hexdigest()
    if integrity.get("hash") != whole_hash:
        raise RuntimeError("worker.js whole-file integrity check failed")

    block_hashes = integrity_block_hashes(worker_bytes, block_size)
    if blocks != block_hashes:
        raise RuntimeError("worker.js block integrity check failed")
    return whole_hash


def integrity_block_hashes(worker_bytes: bytes, block_size: int) -> list[str]:
    return [
        hashlib.sha256(worker_bytes[start : start + block_size]).hexdigest()
        for start in range(0, len(worker_bytes), block_size)
    ]


def check_archive(archive: Path) -> str:
    """Validate the patched worker and return its whole-file SHA-256."""

    with archive.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as mapping:
        _header, worker, worker_start, worker_end = worker_metadata(mapping)
        worker_bytes = bytes(mapping[worker_start:worker_end])
        worker_hash = verify_worker_integrity(worker_bytes, worker)
        for needle, replacement in WATCHER_PATCHES:
            if worker_bytes.count(needle) != 0:
                raise RuntimeError("unpatched Linux @parcel/watcher call remains")
            if worker_bytes.count(replacement) != 1:
                raise RuntimeError("expected exactly one NixOS fs.watch fallback")
        return worker_hash


def main() -> None:
    check_only = len(sys.argv) == 3 and sys.argv[1] == "--check"
    if check_only:
        print(f"verified {sys.argv[2]} (worker sha256 {check_archive(Path(sys.argv[2]))})")
        return
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} [--check] APP.ASAR")

    if any(len(needle) != len(replacement) for needle, replacement in WATCHER_PATCHES):
        raise RuntimeError("watcher replacement must preserve its byte length")

    archive = Path(sys.argv[1])
    with archive.open("r+b") as stream, mmap.mmap(stream.fileno(), 0) as mapping:
        header, worker, worker_start, worker_end = worker_metadata(mapping)

        worker_bytes = bytes(mapping[worker_start:worker_end])
        verify_worker_integrity(worker_bytes, worker)
        for needle, _replacement in WATCHER_PATCHES:
            if worker_bytes.count(needle) != 1:
                raise RuntimeError("expected exactly one Linux @parcel/watcher call")

        header_size = len(header)
        patched_worker = worker_bytes
        for needle, replacement in WATCHER_PATCHES:
            patched_worker = patched_worker.replace(needle, replacement)
        mapping[worker_start:worker_end] = patched_worker
        block_size = int(worker["integrity"]["blockSize"])
        patched_integrity = {
            **worker["integrity"],
            "hash": hashlib.sha256(patched_worker).hexdigest(),
            "blocks": integrity_block_hashes(patched_worker, block_size),
        }
        new_hash = verify_worker_integrity(
            patched_worker,
            {"integrity": patched_integrity},
        ).encode()
        old_hash = worker["integrity"]["hash"].encode()
        if len(old_hash) != len(new_hash) or header.count(old_hash) != 2:
            raise RuntimeError("unexpected ASAR worker integrity layout")

        header = header.replace(old_hash, new_hash)
        if len(header) != header_size:
            raise RuntimeError("integrity replacement changed the ASAR header size")
        mapping[8 : 8 + header_size] = header
        mapping.flush()

        _final_header, final_worker, final_start, final_end = worker_metadata(mapping)
        if final_start != worker_start or final_end != worker_end:
            raise RuntimeError("worker.js metadata changed its ASAR byte range")
        verify_worker_integrity(bytes(mapping[final_start:final_end]), final_worker)
        final_worker_bytes = bytes(mapping[final_start:final_end])
        for _needle, replacement in WATCHER_PATCHES:
            if final_worker_bytes.count(replacement) != 1:
                raise RuntimeError("patched worker.js marker is missing or duplicated")

    print(f"patched {archive} (worker sha256 {new_hash.decode()})")


if __name__ == "__main__":
    main()
