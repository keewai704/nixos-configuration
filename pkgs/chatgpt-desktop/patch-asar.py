"""Patch the Linux Git watcher and text selection in the ChatGPT ASAR bundle.

The bundled @parcel/watcher native module crashes during worker startup on
NixOS. The worker already contains an fs.watch implementation for the other
platforms, and Node's native recursive watcher is suitable for local Git
working trees here. The shared selection style uses blue with white text for
readability in both themes. Keep each replacement byte-for-byte the same size
so ASAR offsets remain valid and update the corresponding integrity entries.
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
        (
            b"startMetadataWatch:(t,n)=>t.isLocal?process.platform===`linux`&&n.recursive!==!1?"
            b"F9(n,{ignoredPaths:[]}):e.startFileWatch(n):t.startFileWatch(n)"
        ),
        (
            b"startWorkingTreeWatch:(t,n,r)=>t.isLocal?process.platform===`linux`?"
            b"F9(n,{ignoredPaths:[E.posix.join(n.path,`.git`),...r]}):e.startFileWatch(n):"
            b"t.startFileWatch(n)"
        ),
    )
)


SELECTION_NEEDLE = b"::selection{background-color:var(--color-background-text-selection);color:var(--color-text)}"
SELECTION_STYLE = b"::selection{background-color:#2563eb;color:#fff}"
PATCHES = {
    ".vite/build/worker.js": WATCHER_PATCHES,
    "webview/assets/app-initial-5b0a474bff5e.css": (
        (SELECTION_NEEDLE, SELECTION_STYLE.ljust(len(SELECTION_NEEDLE))),
    ),
}


def entry_metadata(mapping: mmap.mmap, path: str) -> tuple[bytearray, dict, int, int]:
    """Read the ASAR header and return the entry's metadata and byte range."""

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
    entry = tree
    for part in path.split("/"):
        entry = entry["files"][part]
    entry_start = header_end + int(entry["offset"])
    entry_end = entry_start + int(entry["size"])
    if entry_start < header_end or entry_end > len(mapping):
        raise RuntimeError("ASAR entry extends past the ASAR archive")
    return header, entry, entry_start, entry_end


def verify_entry_integrity(entry_bytes: bytes, entry: dict) -> str:
    """Check ASAR's whole-file and block SHA-256 integrity metadata."""

    integrity = entry.get("integrity")
    if not isinstance(integrity, dict) or integrity.get("algorithm") != "SHA256":
        raise RuntimeError("ASAR entry does not have SHA256 integrity metadata")

    block_size = int(integrity.get("blockSize", 0))
    blocks = integrity.get("blocks")
    if block_size <= 0 or not isinstance(blocks, list):
        raise RuntimeError("ASAR entry has incomplete integrity metadata")

    whole_hash = hashlib.sha256(entry_bytes).hexdigest()
    if integrity.get("hash") != whole_hash:
        raise RuntimeError("ASAR entry whole-file integrity check failed")

    block_hashes = integrity_block_hashes(entry_bytes, block_size)
    if blocks != block_hashes:
        raise RuntimeError("ASAR entry block integrity check failed")
    return whole_hash


def integrity_block_hashes(entry_bytes: bytes, block_size: int) -> list[str]:
    return [
        hashlib.sha256(entry_bytes[start : start + block_size]).hexdigest()
        for start in range(0, len(entry_bytes), block_size)
    ]


def check_archive(archive: Path) -> None:
    """Validate every replacement and its whole-file and block SHA-256."""

    with (
        archive.open("rb") as stream,
        mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as mapping,
    ):
        for path, patches in PATCHES.items():
            _header, entry, entry_start, entry_end = entry_metadata(mapping, path)
            entry_bytes = bytes(mapping[entry_start:entry_end])
            verify_entry_integrity(entry_bytes, entry)
            for needle, replacement in patches:
                if (
                    entry_bytes.count(needle) != 0
                    or entry_bytes.count(replacement) != 1
                ):
                    raise RuntimeError(
                        f"{path}: expected exactly one replacement and no original"
                    )


def main() -> None:
    check_only = len(sys.argv) == 3 and sys.argv[1] == "--check"
    if check_only:
        check_archive(Path(sys.argv[2]))
        print(f"verified {sys.argv[2]} (watcher, selection, and SHA256 integrity)")
        return
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} [--check] APP.ASAR")

    if any(
        len(needle) != len(replacement)
        for patches in PATCHES.values()
        for needle, replacement in patches
    ):
        raise RuntimeError("replacement must preserve its byte length")

    archive = Path(sys.argv[1])
    with archive.open("r+b") as stream, mmap.mmap(stream.fileno(), 0) as mapping:
        for path, patches in PATCHES.items():
            header, entry, entry_start, entry_end = entry_metadata(mapping, path)

            entry_bytes = bytes(mapping[entry_start:entry_end])
            verify_entry_integrity(entry_bytes, entry)
            for needle, _replacement in patches:
                if entry_bytes.count(needle) != 1:
                    raise RuntimeError("expected exactly one original patch marker")

            header_size = len(header)
            patched_entry = entry_bytes
            for needle, replacement in patches:
                patched_entry = patched_entry.replace(needle, replacement)
            mapping[entry_start:entry_end] = patched_entry
            block_size = int(entry["integrity"]["blockSize"])
            patched_integrity = {
                **entry["integrity"],
                "hash": hashlib.sha256(patched_entry).hexdigest(),
                "blocks": integrity_block_hashes(patched_entry, block_size),
            }
            new_hash = verify_entry_integrity(
                patched_entry,
                {"integrity": patched_integrity},
            ).encode()
            old_hash = entry["integrity"]["hash"].encode()
            if len(old_hash) != len(new_hash) or header.count(old_hash) != 2:
                raise RuntimeError("unexpected ASAR entry integrity layout")

            header = header.replace(old_hash, new_hash)
            if len(header) != header_size:
                raise RuntimeError("integrity replacement changed the ASAR header size")
            mapping[8 : 8 + header_size] = header
            mapping.flush()

            _final_header, final_entry, final_start, final_end = entry_metadata(
                mapping, path
            )
            if final_start != entry_start or final_end != entry_end:
                raise RuntimeError("ASAR entry metadata changed its ASAR byte range")
            verify_entry_integrity(bytes(mapping[final_start:final_end]), final_entry)
            final_entry_bytes = bytes(mapping[final_start:final_end])
            for _needle, replacement in patches:
                if final_entry_bytes.count(replacement) != 1:
                    raise RuntimeError(
                        "patched ASAR entry marker is missing or duplicated"
                    )

    check_archive(archive)
    print(f"patched {archive} (watcher, selection, and SHA256 integrity)")


if __name__ == "__main__":
    main()
