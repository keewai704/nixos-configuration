import base64
import concurrent.futures
import json
from pathlib import Path
import re
import subprocess
import urllib.parse
import urllib.request


def get_json(url):
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.load(response)


def version_key(version):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)+", version):
        raise ValueError(f"Not a stable release: {version}")
    return tuple(int(part) for part in version.split("."))


def latest_linux():
    releases = get_json("https://www.kernel.org/releases.json")["releases"]
    candidates = [
        release
        for release in releases
        if release["moniker"] in {"stable", "mainline"}
        and not release["iseol"]
        and re.fullmatch(r"[0-9]+(?:\.[0-9]+)+", release["version"])
    ]
    return max(candidates, key=lambda release: version_key(release["version"]))


def latest_nvidia():
    endpoint = (
        "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/"
        "services/AjaxDriverService.php"
    )
    candidates = []
    for branch in (0, 1):
        query = urllib.parse.urlencode({
            "func": "DriverManualLookup", "psid": 133, "pfid": 1075,
            "osID": 12, "languageCode": 1033, "beta": 0, "isWHQL": 0,
            "dltype": -1, "dch": 0, "qnf": branch,
            "sort1": 1, "numberOfResults": 1,
        })
        result = get_json(f"{endpoint}?{query}")
        if str(result["Success"]) != "1":
            raise ValueError(f"NVIDIA release lookup failed for branch {branch}")
        for item in result["IDS"]:
            info = item["downloadInfo"]
            if str(info["IsBeta"]) == "0" and info["OsCode"] == "linux64":
                candidates.append(info["DisplayVersion"])
    return max(candidates, key=version_key)


def prefetch(url, unpack=False):
    command = ["nix", "store", "prefetch-file", "--json"]
    if unpack:
        command.append("--unpack")
    result = subprocess.run(
        command + [url], check=True, text=True, stdout=subprocess.PIPE,
    )
    return json.loads(result.stdout)["hash"]


def published_hash(url, filename):
    with urllib.request.urlopen(url, timeout=30) as response:
        for line in response.read().decode().splitlines():
            fields = line.split()
            if len(fields) == 2 and fields[1] == filename and re.fullmatch(r"[0-9a-f]{64}", fields[0]):
                return "sha256-" + base64.b64encode(bytes.fromhex(fields[0])).decode()
    raise ValueError(f"No SHA-256 for {filename} in {url}")


def main():
    path = Path(__file__).with_name("sources.json")
    linux = latest_linux()
    nvidia = latest_nvidia()
    print(f"Latest stable releases: Linux {linux['version']}, NVIDIA {nvidia}", flush=True)
    if path.exists():
        previous = json.loads(path.read_text())
        for name, version in (("linux", linux["version"]), ("nvidia", nvidia)):
            if version_key(version) < version_key(previous[name]["version"]):
                raise ValueError(f"Refusing to downgrade {name} to {version}")
        if previous["linux"]["version"] == linux["version"] and previous["nvidia"]["version"] == nvidia:
            print("Sources are already current")
            return
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
        kernel_url, kernel_filename = linux["source"].rsplit("/", 1)
        kernel_hash = pool.submit(published_hash, f"{kernel_url}/sha256sums.asc", kernel_filename)
        driver_filename = f"NVIDIA-Linux-x86_64-{nvidia}.run"
        driver_hash = pool.submit(
            published_hash,
            f"https://us.download.nvidia.com/XFree86/Linux-x86_64/{nvidia}/"
            f"{driver_filename}.sha256sum", driver_filename,
        )
        source_hashes = {
            key: pool.submit(
                prefetch, f"https://github.com/NVIDIA/{repo}/archive/{nvidia}.tar.gz", True,
            )
            for key, repo in {
                "openSha256": "open-gpu-kernel-modules",
                "settingsSha256": "nvidia-settings",
                "persistencedSha256": "nvidia-persistenced",
            }.items()
        }
        sources = {
            "linux": {
                "version": linux["version"], "url": linux["source"],
                "hash": kernel_hash.result(),
            },
            "nvidia": {
                "version": nvidia, "sha256_64bit": driver_hash.result(),
                **{key: future.result() for key, future in source_hashes.items()},
            },
        }
    content = json.dumps(sources, indent=2) + "\n"
    if not path.exists() or path.read_text() != content:
        temporary = path.with_suffix(".json.tmp")
        temporary.write_text(content)
        temporary.replace(path)
        print(f"Updated {path}")
    else:
        print("Sources are already current")


if __name__ == "__main__":
    main()
