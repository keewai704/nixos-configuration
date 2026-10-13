import fcntl
import os
from pathlib import Path
import stat
import sys


def main():
    if len(sys.argv) < 2 or not os.path.isabs(sys.argv[1]):
        raise ValueError("An absolute DSH executable is required")
    configured = os.environ.get("DSH_HOME", "").strip()
    home = Path(configured).expanduser().absolute() if configured else Path.home() / ".dsh"
    for parent in home.parents:
        try:
            ancestor = parent.lstat()
        except FileNotFoundError:
            continue
        if not stat.S_ISDIR(ancestor.st_mode) or (parent != parent.parent and ancestor.st_uid not in (0, os.getuid())):
            raise ValueError("DSH_HOME ancestors must be real directories owned by root or the current user")
        if ancestor.st_mode & 0o022 and not (ancestor.st_uid == 0 and ancestor.st_mode & stat.S_ISVTX):
            raise ValueError("DSH_HOME ancestor is writable by other users")
    home.mkdir(mode=0o700, parents=True, exist_ok=True)
    home_stat = home.lstat()
    if not stat.S_ISDIR(home_stat.st_mode) or home_stat.st_uid != os.getuid():
        raise ValueError("DSH_HOME must be a directory owned by the current user, not a symlink")
    if home_stat.st_mode & 0o022:
        raise ValueError("DSH_HOME must not be writable by other users")
    lock = home / ".operations.lock"
    fd = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid():
            raise ValueError("Unsafe operations lock")
        if info.st_mode & 0o022:
            raise ValueError("Operations lock must not be writable by other users")
        try:
            fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except BlockingIOError:
            print("DSH offline maintenance holds the exclusive lock; try again after it finishes.", file=sys.stderr)
            return 75
        current = lock.lstat()
        if (info.st_dev, info.st_ino) != (current.st_dev, current.st_ino):
            raise ValueError("Operations lock changed during acquisition")
        for relative in ("operations", "operations/migrations", "storages"):
            path = home / relative
            try:
                state = path.lstat()
            except FileNotFoundError:
                continue
            if not stat.S_ISDIR(state.st_mode) or state.st_uid != os.getuid() or state.st_mode & 0o022:
                raise ValueError("Unsafe maintenance state directory")
        for relative in ("operations/migrations/active.json", "storages/.retention-workspace.json", "storages/.retention-workspace.tmp"):
            if os.path.lexists(home / relative):
                raise ValueError("Incomplete offline maintenance requires explicit recovery before DSH can start")
        os.set_inheritable(fd, True)
        os.environ["DSH_HOME"] = str(home)
        os.execv(sys.argv[1], sys.argv[1:])
    finally:
        os.close(fd)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"dsh: {error}", file=sys.stderr)
        sys.exit(1)
