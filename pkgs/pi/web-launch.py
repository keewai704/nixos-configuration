import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile


def password_path():
    state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "pi-web"
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    state.chmod(0o700)
    return state / "password"


def load_password():
    path = password_path()
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        pass
    else:
        with os.fdopen(descriptor, "w") as handle:
            handle.write(secrets.token_urlsafe(32) + "\n")
    if path.is_symlink() or not path.is_file() or path.stat().st_mode & 0o077:
        raise RuntimeError("Pi Web password must be a private regular file (0600)")
    password = path.read_text().strip()
    if not password:
        raise RuntimeError("Pi Web password must not be empty")
    return password


def main():
    password = load_password()
    if sys.argv[1:] == ["--show-password"]:
        print(password)
        return

    package, node = sys.argv[1:]
    modules = Path(package) / "lib/pi/node_modules"
    runtime = Path(os.environ["RUNTIME_DIRECTORY"])
    runtime.chmod(0o700)
    directory = Path(tempfile.mkdtemp(prefix="server-", dir=runtime)) / "app"
    shutil.copytree(modules / "@agegr/pi-web", directory, copy_function=shutil.copyfile)
    for root, directories, files in os.walk(directory):
        Path(root).chmod(0o700)
        for name in files:
            (Path(root) / name).chmod(0o600)
    (directory / "node_modules").symlink_to(modules, target_is_directory=True)
    subprocess.run(
        [node, "-e", "const {rotatePreviewSecrets} = require('./bin/rotate-preview-secrets.js'); if (!rotatePreviewSecrets('.next').ok) process.exit(1)"],
        cwd=directory,
        check=True,
    )
    os.environ["PI_WEB_PASSWORD"] = password
    os.execv(node, [node, str(directory / "bin/pi-web.js"), "--no-open", "--hostname", "127.0.0.1", "--port", "30141"])


if __name__ == "__main__":
    main()
