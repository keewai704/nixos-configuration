import fcntl
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class LaunchLockTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dsh-launch-lock-")
        self.home = Path(self.temporary.name)
        self.script = Path(__file__).with_name("launch-lock.py")
        self.environment = {**os.environ, "DSH_HOME": str(self.home)}

    def tearDown(self):
        self.temporary.cleanup()

    def run_locked(self, code):
        return subprocess.run([sys.executable, self.script, sys.executable, "-c", code], env=self.environment, capture_output=True, text=True, timeout=10)

    def test_shared_lock_is_inherited_through_exec(self):
        result = self.run_locked("import os,fcntl; fd=os.open(os.environ['DSH_HOME']+'/.operations.lock',os.O_RDONLY);\ntry: fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)\nexcept BlockingIOError: print('blocked')\nelse: raise RuntimeError('missing shared lock')")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "blocked")
        self.assertEqual((self.home / ".operations.lock").stat().st_mode & 0o777, 0o600)

    def test_maintenance_excludes_launch(self):
        with (self.home / ".operations.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_locked("raise RuntimeError('must not execute')")
        self.assertEqual(result.returncode, 75)
        self.assertIn("offline maintenance", result.stderr)

    def test_shared_launches_can_coexist(self):
        with (self.home / ".operations.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_SH | fcntl.LOCK_NB)
            result = self.run_locked("print('ok')")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_symlink_lock_refused_without_touching_target(self):
        target = self.home / "target"
        target.write_text("unchanged")
        (self.home / ".operations.lock").symlink_to(target)
        result = self.run_locked("print('unsafe')")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(target.read_text(), "unchanged")

    def test_unsafe_home_refused(self):
        self.home.chmod(0o777)
        result = self.run_locked("print('unsafe')")
        self.assertEqual(result.returncode, 1)
        self.assertIn("writable", result.stderr)
        self.home.chmod(0o700)

    def test_unsafe_ancestor_refused_before_creating_home(self):
        parent = self.home / "shared"
        parent.mkdir()
        parent.chmod(0o777)
        self.environment["DSH_HOME"] = str(parent / "new-home")
        result = self.run_locked("print('unsafe')")
        self.assertEqual(result.returncode, 1)
        self.assertIn("ancestor", result.stderr)
        self.assertFalse((parent / "new-home").exists())
        parent.chmod(0o700)

    def test_incomplete_migration_blocks_launch_even_with_terminal_status(self):
        directory = self.home / "operations/migrations"
        directory.mkdir(parents=True)
        (directory / "active.json").write_text('{"status":"committed"}')
        result = self.run_locked("raise RuntimeError('must not execute')")
        self.assertEqual(result.returncode, 1)
        self.assertIn("explicit recovery", result.stderr)

    def test_dangling_active_marker_is_not_ignored(self):
        directory = self.home / "operations/migrations"
        directory.mkdir(parents=True)
        (directory / "active.json").symlink_to(directory / "absent")
        result = self.run_locked("print('unsafe')")
        self.assertEqual(result.returncode, 1)
        self.assertIn("explicit recovery", result.stderr)

    def test_incomplete_retention_blocks_workspace_writers(self):
        directory = self.home / "storages"
        directory.mkdir()
        (directory / ".retention-workspace.tmp").write_text("partial")
        result = self.run_locked("print('unsafe')")
        self.assertEqual(result.returncode, 1)
        self.assertIn("explicit recovery", result.stderr)

    def test_symlinked_maintenance_parent_is_refused(self):
        (self.home / "operations").symlink_to(self.home / "absent")
        result = self.run_locked("print('unsafe')")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Unsafe maintenance", result.stderr)


if __name__ == "__main__":
    unittest.main()
