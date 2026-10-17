#!/usr/bin/env python3
"""Exercise actual runner/lifecycle functions with unprivileged mocks.

No network namespaces are created and no network traffic is sent.
"""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / 'prototypes/od09-isolation/run-mci.sh'
ENV = ROOT / 'test/netns/env.sh'


def run_shell(args, **kwargs):
    """A broken cleanup regression must not leave test processes behind."""
    process = subprocess.Popen(['bash', *args], start_new_session=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, **kwargs)
    try:
        stdout, stderr = process.communicate(timeout=12)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise
    return subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)


class RunnerTests(unittest.TestCase):
    def runner(self, body, files=None):
        with tempfile.TemporaryDirectory() as directory:
            for name, content in (files or {}).items():
                (Path(directory) / name).write_text(content)
            return run_shell(['-c', 'source "$1"; raw=$2; env_sh=/bin/true; '
                              'pids=(); ' + body, 'fixture', str(RUNNER), directory])

    def test_failed_receiver_is_forgotten(self):
        result = self.runner('''
            bash -c 'exit 7' & pid=$!
            pids=($pid); receiver_pids=($pid); labels=(failed)
            if finish_case; then exit 9; fi
            test "${#pids[@]}" -eq 0
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('INVALID experiment', result.stderr)

    def test_exited_capture_is_invalid_and_forgotten(self):
        result = self.runner('''
            true & pid=$!
            pids=($pid); capture_pids=($pid)
            sleep 0.1
            if stop_captures; then exit 9; fi
            test "${#pids[@]}" -eq 0
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('capture exited before', result.stderr)

    def test_capture_safety_timeout_is_invalid(self):
        result = self.runner('''
            bash -c 'exit 124' & pid=$!
            pids=($pid); capture_pids=($pid)
            sleep 0.1
            if stop_captures; then exit 9; fi
            test "${#pids[@]}" -eq 0
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('INVALID experiment', result.stderr)

    def test_cleanup_escalates_for_term_ignoring_child(self):
        start = time.monotonic()
        result = self.runner('''
            bash -c 'trap "" TERM; touch "$1"; while :; do sleep 0.1; done' \
                fixture "$raw/child.ready" &
            pids=($!)
            wait_until 2 test -f "$raw/child.ready"
            trap cleanup EXIT
            exit 1
        ''')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('INVALID run', result.stderr)
        self.assertLess(time.monotonic() - start, 6)

    def test_cleanup_failure_invalidates_otherwise_successful_run(self):
        result = self.runner('env_sh=/bin/false; trap cleanup EXIT; exit 0')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('namespace cleanup failed', result.stderr)
        self.assertIn('INVALID run', result.stderr)

    def test_unreadable_igmp_evidence_is_invalid(self):
        result = self.runner('''
            recv() { :; }; send() { :; }; finish_case() { :; }
            expect_accept() { :; }; result() { :; }
            capture() { :; }; stop_captures() { :; }
            count_matches() { printf '1\\n'; return 2; }
            run_case group 0
        ''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('cannot read IGMP evidence', result.stderr)

    def test_result_compares_rejection_reasons(self):
        summary = json.dumps({'name': 'fixture', 'received': 400,
                              'verdicts': {'accept': 200, 'wrong_destination': 200},
                              'foreign_delivered': 200,
                              'options': {'bind': 'wildcard', 'mcall': '0',
                                          'mcall_effective': 0}})
        result = self.runner('''
            result CASE fixture 200 '{"wrong_ingress":200}'
            test "${#mismatches[@]}" -eq 1
            [[ ${rows[0]} == *'| NO |'* ]]
        ''', {'fixture.json': summary})
        self.assertEqual(result.returncode, 0, result.stderr)

    def namespace(self, mode):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            mocks = {
                'id': '#!/bin/sh\nprintf "0\\n"\n',
                'sysctl': '#!/bin/sh\nexit 0\n',
                'ip': '''#!/bin/sh
printf '%s\\n' "$*" >> "$MOCK_LOG"
case "$1 $2" in
    'netns list')
        [ "$MOCK_MODE" != list_failure ] || exit 8
        printf 'mcgw-fixture\\n'
        ;;
    'netns pids')
        [ "$MOCK_MODE" != pids_failure ] || exit 8
        ;;
    'netns del') [ "$MOCK_MODE" != delete_failure ] || exit 8 ;;
    *) exit 9 ;;
esac
''',
            }
            for name, contents in mocks.items():
                target = path / name
                target.write_text(contents)
                target.chmod(0o755)
            log = path / 'commands'
            environment = {**os.environ, 'PATH': directory + ':' + os.environ['PATH'],
                           'MOCK_MODE': mode, 'MOCK_LOG': str(log)}
            result = run_shell([str(ENV), 'down'], env=environment)
            return result, log.read_text()

    def test_namespace_deletion_success(self):
        result, commands = self.namespace('success')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ENV down', result.stdout)
        self.assertIn('netns del mcgw-fixture', commands)

    def test_namespace_failures_are_not_reported_as_success(self):
        for mode in ('list_failure', 'pids_failure', 'delete_failure'):
            with self.subTest(mode=mode):
                result, commands = self.namespace(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('ENV down', result.stdout)
                if mode != 'delete_failure':
                    self.assertNotIn('netns del', commands)


if __name__ == '__main__':
    unittest.main()
