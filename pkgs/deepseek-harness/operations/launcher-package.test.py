import fcntl
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest


class PackagedLauncherTests(unittest.TestCase):
    def test_actual_node_process_retains_shared_lock(self):
        package = Path(os.environ["DSH_TEST_PACKAGE"])
        with tempfile.TemporaryDirectory(prefix="dsh-packaged-lock-") as root:
            home = Path(root) / "home"
            home.mkdir(mode=0o700)
            probe = Path(root) / "probe.cjs"
            probe.write_text("""const fs = require('node:fs');
const path = require('node:path');
if (process.argv[1]?.endsWith('/lib/bin.js')) {
  const expected = fs.statSync(path.join(process.env.DSH_HOME, '.operations.lock'));
  const held = fs.readdirSync('/proc/self/fd').some(fd => {
    try {
      const info = fs.fstatSync(Number(fd));
      return info.dev === expected.dev && info.ino === expected.ino && /FLOCK\\s+ADVISORY\\s+READ/.test(fs.readFileSync('/proc/self/fdinfo/' + fd, 'utf8'));
    } catch { return false; }
  });
  if (!held) throw new Error('Packaged DSH Node process has no inherited shared lock');
  fs.writeFileSync(process.env.DSH_LOCK_PROOF, 'held');
  process.exit(0);
}
""")
            proof = Path(root) / "proof"
            environment = {**os.environ, "DSH_HOME": str(home), "HOME": str(Path(root)), "NODE_OPTIONS": f"--require={probe}", "DSH_LOCK_PROOF": str(proof)}
            result = subprocess.run([package / "bin/dsh", "--version"], env=environment, capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(proof.read_text(), "held")
            lock = home / ".operations.lock"
            with lock.open() as handle:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                blocked = subprocess.run([package / "bin/dsh", "--version"], env=environment, capture_output=True, text=True, timeout=15)
                self.assertEqual(blocked.returncode, 75, blocked.stderr)
                self.assertIn("offline maintenance", blocked.stderr)


if __name__ == "__main__":
    unittest.main()
