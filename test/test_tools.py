#!/usr/bin/env python3
"""Process checks: loopback listeners only; no packets leave the host.

Run: python3 test/test_tools.py (needs Go on PATH)
"""
import json
from pathlib import Path
import shutil
import signal
import socket
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
        for tool, package in (("mcrecv", "./test/tools/mcrecv"),
                              ("mcsend", "./test/tools/mcsend"),
                              ("od09-isolation", "./prototypes/od09-isolation")):
            subprocess.run(["go", "build", "-o", str(cls.bin / tool),
                            package], cwd=ROOT, check=True)

    def receiver_args(self, tool):
        if tool == "mcrecv":
            return [str(self.bin / tool), "-listen", "127.0.0.1:0"]
        # The prototype requires a nonzero port. Select an unused one without
        # touching any physical interface; the multicast membership is only on
        # lo and these lifecycle checks never transmit multicast datagrams.
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        return [str(self.bin / tool), "-group", "239.1.1.1", "-iface", "lo",
                "-port", str(port)]

    def test_deadline_completes_window(self):
        for tool in ("mcrecv", "od09-isolation"):
            with self.subTest(tool=tool):
                started = time.monotonic()
                result = subprocess.run([*self.receiver_args(tool), "-duration", "100ms"],
                                        capture_output=True, text=True, timeout=5, check=False)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertGreaterEqual(time.monotonic() - started, 0.09)
                summary = json.loads(result.stdout)
                self.assertTrue(summary["complete"])
                self.assertEqual(summary["termination"], "deadline")
                self.assertEqual(summary["received"], 0)

    def test_signal_is_incomplete_and_ready_marker_exists(self):
        for tool in ("mcrecv", "od09-isolation"):
            for sig in (signal.SIGTERM, signal.SIGINT):
                with self.subTest(tool=tool, signal=sig):
                    ready = self.bin / f"{tool}-{sig}.ready"
                    with subprocess.Popen([*self.receiver_args(tool), "-duration", "30s",
                                           "-ready-file", str(ready)], stdout=subprocess.PIPE,
                                          stderr=subprocess.PIPE, text=True) as child:
                        try:
                            deadline = time.monotonic() + 3
                            while (not ready.exists() and child.poll() is None
                                   and time.monotonic() < deadline):
                                time.sleep(0.01)
                            self.assertTrue(ready.exists(), "receiver never announced readiness")
                            self.assertEqual(ready.read_text(), "ready\n")
                            child.send_signal(sig)
                            stdout, stderr = child.communicate(timeout=5)
                            self.assertEqual(child.returncode, 1, stderr)
                            summary = json.loads(stdout)
                            self.assertFalse(summary["complete"])
                            self.assertEqual(summary["termination"], "closed")
                        finally:
                            if child.poll() is None:
                                child.kill()
                                child.communicate()

    def test_readiness_write_failure_is_setup_failure(self):
        for tool in ("mcrecv", "od09-isolation"):
            with self.subTest(tool=tool):
                ready = self.bin / "missing-directory" / f"{tool}.ready"
                result = subprocess.run([*self.receiver_args(tool), "-ready-file", str(ready)],
                                        capture_output=True, text=True, timeout=5, check=False)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("readiness marker", result.stderr)
                self.assertFalse(ready.exists())
                self.assertEqual(result.stdout, "")

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

    def test_trailing_arguments_cannot_hide_flags(self):
        for tool in ("mcrecv", "mcsend", "od09-isolation"):
            with self.subTest(tool=tool):
                # Rejection must happen before socket setup; no network operation
                # is needed to diagnose a misspelled positional argument.
                result = subprocess.run([str(self.bin / tool), "unexpected", "-ignored"],
                                        capture_output=True, text=True, timeout=5, check=False)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("unexpected positional arguments", result.stderr)
                self.assertEqual(result.stdout, "")

    def test_ttl_range_is_validated_even_for_unicast(self):
        for ttl in (-2, -1, 0, 255, 256):
            with self.subTest(ttl=ttl):
                # -n 0 validates a real socket setup without emitting packets.
                result = subprocess.run([str(self.bin / "mcsend"), "-to", "127.0.0.1:9",
                                         "-n", "0", "-ttl", str(ttl)], capture_output=True,
                                        text=True, timeout=5, check=False)
                if 0 <= ttl <= 255:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(json.loads(result.stdout)["sent"], 0)
                else:
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertIn("-ttl must be between 0 and 255", result.stderr)

    def test_receiver_reports_bound_port(self):
        result = subprocess.run([str(self.bin / "mcrecv"), "-listen", "127.0.0.1:0",
                                 "-duration", "100ms"], capture_output=True, text=True,
                                timeout=5, check=False)
        self.assertNotEqual(json.loads(result.stdout)["listen"], "127.0.0.1:0")


if __name__ == "__main__":
    unittest.main()
