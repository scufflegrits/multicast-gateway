#!/usr/bin/env python3
"""Unprivileged harness regressions; no packets or namespace changes."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

HELPERS = Path(__file__).with_name("harness.sh")


class HarnessTests(unittest.TestCase):
    def run_check(self, command, contents=None):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "evidence.json"
            if contents is not None:
                evidence.write_text(contents)
            return subprocess.run(
                ["bash", "-c", 'set -euo pipefail; source "$1"; ' + command,
                 "fixture", str(HELPERS), str(evidence)],
                capture_output=True, text=True, check=False,
            )

    def test_zero_igmp_matches_is_data(self):
        result = self.run_check('count_matches "v3 report" "$2"', "IGMP v2 report\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "0")

    def test_unreadable_evidence_fails(self):
        self.assertNotEqual(self.run_check('count_matches "v3 report" "$2"').returncode, 0)

    def test_failed_child_with_valid_summary_fails(self):
        result = self.run_check('bash -c "exit 7" & pid=$!; wait_receiver "$pid" "$2"',
                                self.receiver())
        self.assertNotEqual(result.returncode, 0)

    def test_receiver_summary_validation(self):
        for contents, valid in [(self.receiver(), True), ("", False), ("garbage", False),
                                (self.receiver(complete=False), False),
                                (self.receiver(termination="read_error"), False),
                                (self.receiver(received=99), False)]:
            with self.subTest(contents=contents):
                result = self.run_check('true & pid=$!; wait_receiver "$pid" "$2"', contents)
                self.assertEqual(result.returncode == 0, valid, result.stderr)

    def test_zero_delivery_fails_positive_control(self):
        result = self.run_check('expect_accept "$2" 200', self.receiver())
        self.assertNotEqual(result.returncode, 0)

    def test_sender_counts_required(self):
        for sent, errors, valid in [(200, 0, True), (0, 0, False), (199, 1, False)]:
            result = self.run_check('check_sender "$2" 200', json.dumps(
                {"tool": "mcsend", "sent": sent, "errors": errors}))
            self.assertEqual(result.returncode == 0, valid, result.stderr)

    def test_capture_timeout_is_expected_but_failure_is_not(self):
        for code, valid in [(0, True), (124, True), (1, False), (127, False)]:
            result = self.run_check(f'bash -c "exit {code}" & pid=$!; wait_capture "$pid"')
            self.assertEqual(result.returncode == 0, valid, result.stderr)

    @staticmethod
    def receiver(**overrides):
        record = {"tool": "od09-isolation", "complete": True, "termination": "deadline",
                  "received": 0, "verdicts": {}}
        record.update(overrides)
        return json.dumps(record)


if __name__ == "__main__":
    unittest.main()
