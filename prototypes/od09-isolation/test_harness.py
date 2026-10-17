#!/usr/bin/env python3
"""Unprivileged harness regressions; no packets or namespace changes.

Run: python3 prototypes/od09-isolation/test_harness.py
"""
import json
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

HELPERS = Path(__file__).with_name('harness.sh')
LIB = Path(__file__).resolve().parents[2] / 'test' / 'netns' / 'lib.sh'

# Decoded tcpdump -vv lines (format confirmed with tcpdump 4.99.5 on synthetic pcaps).
IGMP_LINES = {
    'allow': '    192.168.10.1 > 224.0.0.22: igmp v3 report, 1 group record(s) '
             '[gaddr 232.1.1.1 allow { 192.168.10.20 }]',
    'to_in_multi': '    192.168.10.1 > 224.0.0.22: igmp v3 report, 2 group record(s) '
                   '[gaddr 239.1.1.1 to_ex { }] [gaddr 232.1.1.1 to_in { 192.168.10.21 192.168.10.20 }]',
    'block': '    192.168.10.1 > 224.0.0.22: igmp v3 report, 1 group record(s) '
             '[gaddr 232.1.1.1 block { 192.168.10.20 }]',
    'leave_empty': '    192.168.10.1 > 224.0.0.22: igmp v3 report, 1 group record(s) '
                   '[gaddr 232.1.1.1 to_in { }]',
    'other_host': '    192.168.10.1 > 224.0.0.22: igmp v3 report, 1 group record(s) '
                  '[gaddr 232.1.1.1 allow { 192.168.10.200 }]',
}
UDP_LINE = '    192.168.10.20.40000 > 192.168.10.1.3000: [udp sum ok] UDP, length 64'
BCAST_LINE = '    192.168.10.20.40001 > 192.168.10.255.3000: [udp sum ok] UDP, length 64'


class HarnessTests(unittest.TestCase):
    def run_check(self, command, contents=None):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / 'evidence.json'
            if contents is not None:
                evidence.write_text(contents)
            return subprocess.run(
                ['bash', '-c', 'set -euo pipefail; source "$1"; source "$3"; ' + command,
                 'fixture', str(HELPERS), str(evidence), str(LIB)],
                capture_output=True, text=True, check=False,
            )

    def assert_invalid(self, result):
        self.assertNotEqual(result.returncode, 0)
        # A failure must come from the validator, not from a jq error or missing tool.
        self.assertIn('INVALID experiment', result.stderr)

    # count_matches: zero matches is data, unreadable evidence is failure.
    def test_zero_igmp_matches_is_data(self):
        result = self.run_check('count_matches "v3 report" "$2"', 'IGMP v2 report\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), '0')

    def test_unreadable_evidence_fails(self):
        self.assertNotEqual(self.run_check('count_matches "v3 report" "$2"').returncode, 0)

    def test_od17_capture_patterns_count_exactly(self):
        lines = '\n'.join(['    IP (tos 0x0, ttl 64, proto UDP (17), length 92)', UDP_LINE,
                           BCAST_LINE, UDP_LINE]) + '\n'
        result = self.run_check(r"""count_matches ' > 192\.168\.10\.(1|255)\.3000:' "$2" """, lines)
        self.assertEqual(result.stdout.strip(), '3', result.stderr)

    def test_igmp_join_pattern_matches_joins_only(self):
        expected = {'allow': '1', 'to_in_multi': '1', 'block': '0', 'leave_empty': '0',
                    'other_host': '0'}
        for name, line in IGMP_LINES.items():
            with self.subTest(record=name):
                result = self.run_check('count_matches "$IGMP_JOIN_RE" "$2"', line + '\n')
                self.assertEqual(result.stdout.strip(), expected[name], result.stderr)

    # Receiver summaries and positive controls.
    def test_failed_child_with_valid_summary_fails(self):
        result = self.run_check('bash -c "exit 7" & pid=$!; wait_receiver "$pid" "$2"',
                                self.receiver())
        self.assert_invalid(result)

    def test_receiver_summary_validation(self):
        two = self.receiver() + '\n' + self.receiver()
        for contents, valid in [(self.receiver(), True), ('', False), ('garbage', False),
                                (self.receiver(complete=False), False),
                                (self.receiver(termination='read_error'), False),
                                (self.receiver(received=99), False),
                                (self.receiver(received='0'), False),
                                (self.receiver(tool='mcrecv'), False), (two, False)]:
            with self.subTest(contents=contents):
                result = self.run_check('true & pid=$!; wait_receiver "$pid" "$2"', contents)
                if valid:
                    self.assertEqual(result.returncode, 0, result.stderr)
                else:
                    self.assert_invalid(result)

    def test_positive_control_requires_exact_count(self):
        for accepted, valid in [(200, True), (199, False), (201, False), (0, False)]:
            with self.subTest(accepted=accepted):
                result = self.run_check('expect_accept "$2" 200', self.receiver(
                    received=accepted, verdicts={'accept': accepted} if accepted else {}))
                if valid:
                    self.assertEqual(result.returncode, 0, result.stderr)
                else:
                    self.assert_invalid(result)

    def test_sender_counts_required(self):
        for record, valid in [({'sent': 200, 'errors': 0}, True), ({'sent': 0, 'errors': 0}, False),
                              ({'sent': 199, 'errors': 1}, False),
                              ({'sent': 200, 'errors': 1}, False),
                              ({'sent': 200, 'errors': 0, 'tool': 'other'}, False)]:
            with self.subTest(record=record):
                result = self.run_check('check_sender "$2" 200',
                                        json.dumps({'tool': 'mcsend', **record}))
                if valid:
                    self.assertEqual(result.returncode, 0, result.stderr)
                else:
                    self.assert_invalid(result)

    def test_capture_exit_codes(self):
        # 143 is intentional shutdown; a safety timeout means incomplete evidence.
        for code, valid in [(0, True), (124, False), (137, False), (143, True), (1, False), (127, False)]:
            with self.subTest(code=code):
                result = self.run_check(f'bash -c "exit {code}" & pid=$!; wait_capture "$pid"')
                if valid:
                    self.assertEqual(result.returncode, 0, result.stderr)
                else:
                    self.assert_invalid(result)

    # Prediction checks report data; they never call invalid().
    def test_foreign_matches(self):
        for foreign, predicted, valid in [(0, 0, True), (200, 200, True), (0, 200, False),
                                          (200, 0, False)]:
            with self.subTest(foreign=foreign, predicted=predicted):
                result = self.run_check(f'foreign_matches "$2" {predicted}',
                                        self.receiver(foreign_delivered=foreign))
                self.assertEqual(result.returncode == 0, valid, result.stderr)
                self.assertNotIn('INVALID', result.stderr)

    def test_mcall_matches(self):
        for requested, effective, valid in [('default', 1, True), ('0', 0, True), ('1', 1, True),
                                            ('default', 0, False), ('0', 1, False)]:
            with self.subTest(requested=requested, effective=effective):
                result = self.run_check('mcall_matches "$2"', self.receiver(
                    options={'mcall': requested, 'mcall_effective': effective}))
                self.assertEqual(result.returncode == 0, valid, result.stderr)

    def test_row_text(self):
        summary = self.receiver(name='R1-01-wildcard-default', received=400,
                                foreign_delivered=200,
                                verdicts={'accept': 200, 'wrong_destination': 200},
                                options={'bind': 'wildcard', 'mcall': 'default',
                                         'mcall_effective': 1})
        result = self.run_check('row_text T-MCI-01 "$2" 200 yes', summary)
        self.assertEqual(result.stdout.strip(),
                         '| T-MCI-01 | R1-01-wildcard-default | wildcard | default (1) | 400 | 200 '
                         '| 200 | 200 | yes | wrong_destination=200 |', result.stderr)
        accept_only = self.receiver(name='R', received=200, verdicts={'accept': 200},
                                    options={'bind': 'group', 'mcall': '0', 'mcall_effective': 0})
        result = self.run_check('row_text C "$2" 0 yes', accept_only)
        self.assertTrue(result.stdout.strip().endswith('| 0 | yes |  |'), result.stdout)

    def test_rejection_reasons_must_match_even_with_same_total(self):
        contents = self.receiver(received=1000, foreign_delivered=800,
                                 verdicts={'accept': 200, 'wrong_destination': 800})
        result = self.run_check(
            "rejections_match \"$2\" '{\"wrong_destination\":400,\"wrong_ingress\":400}'", contents)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('INVALID', result.stderr)
        result = self.run_check(
            "rejections_match \"$2\" '{\"wrong_destination\":800,\"wrong_ingress\":0}'", contents)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_summary_origin_and_counter_integrity(self):
        own = {'dst': '239.1.1.1', 'ifindex': 2, 'src': '192.168.10.20',
               'verdict': 'accept', 'count': 200}
        good = {'received': 200, 'verdicts': {'accept': 200}, 'origins': [own]}
        for overrides, valid in [
            (good, True),
            ({**good, 'foreign_delivered': 200}, False),
            ({**good, 'foreign_delivered': -1}, False),
            ({**good, 'verdicts': {'accept': 201, 'oversize': -1}}, False),
            ({**good, 'origins': []}, False),
            ({**good, 'origins': [{**own, 'count': 200.5}]}, False),
            ({**good, 'origins': [{**own, 'dst': '192.168.10.1'}],
              'foreign_delivered': 200}, False),
            ({**good, 'verdicts': {'unexpected_verdict': 200},
              'origins': [{**own, 'verdict': 'unexpected_verdict'}]}, False),
            ({**good, 'options': {}}, False),
        ]:
            with self.subTest(overrides=overrides):
                result = self.run_check('true & pid=$!; wait_receiver "$pid" "$2"',
                                        self.receiver(**overrides))
                if valid:
                    self.assertEqual(result.returncode, 0, result.stderr)
                else:
                    self.assert_invalid(result)

    # wait_until (test/netns/lib.sh) waits the full requested time.
    def test_wait_until(self):
        self.assertEqual(self.run_check('wait_until 1 true').returncode, 0)
        start = time.monotonic()
        result = self.run_check('wait_until 1 false')
        elapsed = time.monotonic() - start
        self.assertNotEqual(result.returncode, 0)
        self.assertGreaterEqual(elapsed, 0.9)
        self.assertLess(elapsed, 3)
        result = self.run_check('(sleep 0.5; touch "$2") & wait_until 2 test -f "$2"')
        self.assertEqual(result.returncode, 0, result.stderr)

    @staticmethod
    def receiver(**overrides):
        record = {'tool': 'od09-isolation', 'complete': True, 'termination': 'deadline',
                  'name': 'R', 'go': 'test-toolchain', 'received': 0, 'foreign_delivered': 0,
                  'verdicts': {}, 'origins': [],
                  'options': {'group': '239.1.1.1', 'source': '', 'iface': 'eth0',
                              'ifindex': 2, 'port': 3000, 'bind': 'group',
                              'mcall': 'default', 'mcall_effective': 1}}
        record.update(overrides)
        return json.dumps(record)


if __name__ == '__main__':
    unittest.main()
