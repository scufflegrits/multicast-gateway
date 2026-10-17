#!/usr/bin/env python3
"""Process checks: loopback listeners only; no packets leave the host.

Run: python3 test/test_tools.py (needs Go on PATH)
"""
import json
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('go'), 'Go toolchain not on PATH')
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
        # Linux udp_sendmsg rejects destination port 0 with EINVAL before
        # routing, so this never emits a packet.
        result = subprocess.run([str(self.bin / "mcsend"), "-to", "127.0.0.1:0",
                                 "-n", "2", "-rate", "1000"],
                                capture_output=True, text=True, timeout=5, check=False)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("first error", result.stderr)
        summary = json.loads(result.stdout)
        self.assertEqual(summary["sent"], 0)
        self.assertEqual(summary["errors"], 2)
        self.assertEqual(summary["n"], 2)

    def test_usage_errors_exit_2(self):
        for args in (["-to", "127.0.0.1:9", "-size", "65508"],
                     ["-to", "127.0.0.1:9", "-iface", "no-such-interface"],
                     ["-to", "127.0.0.1:9", "-rate", "0"]):
            with self.subTest(args=args):
                result = subprocess.run([str(self.bin / "mcsend"), *args], capture_output=True,
                                        text=True, timeout=5, check=False)
                self.assertEqual(result.returncode, 2, result.stderr)

    def test_receiver_reports_bound_port(self):
        result = subprocess.run([str(self.bin / "mcrecv"), "-listen", "127.0.0.1:0",
                                 "-duration", "100ms"], capture_output=True, text=True,
                                timeout=5, check=False)
        self.assertNotEqual(json.loads(result.stdout)["listen"], "127.0.0.1:0")


if __name__ == "__main__":
    unittest.main()
