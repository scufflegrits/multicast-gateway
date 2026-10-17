#!/usr/bin/env python3
"""Process checks: loopback listeners only; oversized sends fail before transmission."""
import json
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ToolProcesses(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.directory.cleanup)
        cls.bin = Path(cls.directory.name)
        for tool in ("mcrecv", "mcsend"):
            subprocess.run(["go", "build", "-o", str(cls.bin / tool),
                            f"./test/tools/{tool}"], cwd=ROOT, check=True)

    def test_deadline_completes_window(self):
        result = subprocess.run([str(self.bin / "mcrecv"), "-listen", "127.0.0.1:0",
                                 "-duration", "100ms"], capture_output=True, text=True,
                                timeout=5, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        summary = json.loads(result.stdout)
        self.assertTrue(summary["complete"])
        self.assertEqual(summary["termination"], "deadline")

    def test_signal_is_incomplete_and_ready_marker_exists(self):
        ready = self.bin / "receiver.ready"
        with subprocess.Popen([str(self.bin / "mcrecv"), "-listen", "127.0.0.1:0",
                               "-duration", "30s", "-ready-file", str(ready)],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as child:
            try:
                deadline = time.monotonic() + 3
                while not ready.exists() and child.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(ready.exists(), "receiver never announced readiness")
                child.send_signal(signal.SIGTERM)
                stdout, stderr = child.communicate(timeout=5)
                self.assertEqual(child.returncode, 1, stderr)
                summary = json.loads(stdout)
                self.assertFalse(summary["complete"])
                self.assertEqual(summary["termination"], "closed")
            finally:
                if child.poll() is None:
                    child.kill()
                    child.communicate()

    def test_failed_submission_returns_nonzero_with_summary(self):
        # IPv4 UDP payload limit is 65507; this never emits an actual packet.
        result = subprocess.run([str(self.bin / "mcsend"), "-to", "127.0.0.1:9",
                                 "-n", "1", "-size", "65508", "-rate", "1000"],
                                capture_output=True, text=True, timeout=5, check=False)
        self.assertEqual(result.returncode, 1, result.stderr)
        summary = json.loads(result.stdout)
        self.assertEqual(summary["sent"], 0)
        self.assertEqual(summary["errors"], 1)


if __name__ == "__main__":
    unittest.main()
