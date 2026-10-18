#!/usr/bin/env python3
"""Exercise actual runner/lifecycle functions with unprivileged mocks.

No network namespaces are created and no network traffic is sent.
"""
import hashlib
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
            expect_accept() { :; }; expect_accept_source() { :; }; result() { :; }
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

    def test_publication_requires_cleanup_and_does_not_repeat_it(self):
        for cleanup_success in (True, False):
            with self.subTest(cleanup_success=cleanup_success):
                result = self.runner('''
                    report=$raw/report.md; out=$raw/published.md; owner=()
                    env_sh=$raw/env
                    chmod +x "$env_sh"
                    if publish_report; then
                        test -f "$out"
                        teardown_environment
                        echo published
                    else
                        test ! -e "$out"
                        echo blocked
                    fi
                    test "$(wc -l < "$raw/down.calls")" -eq 1
                    test -f "$report"
                ''', {'report.md': '| Run status | **VALID** |\n',
                      'env': '#!/bin/sh\necho down >> "${0%/*}/down.calls"\nexit ' +
                             ('0' if cleanup_success else '1') + '\n'})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), 'published' if cleanup_success else 'blocked')
                if not cleanup_success:
                    self.assertIn('cleanup failed before publication', result.stderr)

    def test_publication_refuses_existing_file_and_symlink(self):
        for target in ('printf old > "$out"', 'ln -s "$raw/victim" "$out"'):
            with self.subTest(target=target):
                result = self.runner('''
                    report=$raw/report.md; out=$raw/published.md; owner=()
                    printf old > "$raw/victim"
                ''' + target + '''
                    if publish_report; then exit 9; fi
                    test "$(cat "$out")" = old
                    test "$(cat "$raw/victim")" = old
                ''', {'report.md': 'new\n'})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('refusing to overwrite', result.stderr)

    def test_publication_cannot_overwrite_a_racing_target(self):
        result = self.runner('''
            report=$raw/report.md; out=$raw/published.md; owner=()
            ln() { printf raced > "$out"; command ln "$@"; }
            if publish_report; then exit 9; fi
            test "$(cat "$out")" = raced
            test -z "$(find "$raw" -name '.od09-report.*' -print)"
        ''', {'report.md': 'new\n'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('could not publish report', result.stderr)

    def test_binary_snapshots_preserve_the_selected_bytes(self):
        script = '#!/bin/sh\nexit 0\n'
        digest = hashlib.sha256(script.encode()).hexdigest()
        result = self.runner('''
            mkdir "$raw/input"
            cp "$raw/tool" "$raw/input/mcsend"
            cp "$raw/tool" "$raw/input/od09-isolation"
            bin=$raw/input
            snapshot_binaries
            printf changed > "$raw/input/mcsend"
            test "$bin" = "$raw/bin"
            test -x "$bin/mcsend"
            (cd "$bin" && sha256sum -c "$raw/binary-sha256.txt")
            cat "$raw/binary-sha256.txt"
            grep -q 'source revision unknown' "$raw/mcsend.buildinfo"
        ''', {'tool': script})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count(digest), 2)

    def test_environment_lock_excludes_other_opens_and_allows_inheritance(self):
        result = self.runner('''
            lock_environment "$raw/environment.lock"
            # A child reuses the inherited lock description without deadlocking.
            bash -c 'source "$1"; lock_environment "$2"' fixture \
                "$repo/test/netns/lib.sh" "$raw/environment.lock"
            # A fresh open competes, even from a descendant.
            if bash -c 'exec 9>&-; source "$1"; lock_environment "$2"' fixture \
                "$repo/test/netns/lib.sh" "$raw/environment.lock"; then exit 9; fi
            exec 9>&-
            bash -c 'source "$1"; lock_environment "$2"' fixture \
                "$repo/test/netns/lib.sh" "$raw/environment.lock"
        ''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('environment is in use', result.stderr)

    def test_main_uses_selected_executable_evidence_parent(self):
        result = self.runner('''
            fixture=$raw
            mkdir -p "$fixture/repo/test/netns" "$fixture/output/results" \
                "$fixture/input" "$fixture/executable evidence"
            cp /bin/true "$fixture/repo/test/netns/env.sh"
            cp "$fixture/tool" "$fixture/input/mcsend"
            cp "$fixture/tool" "$fixture/input/od09-isolation"
            chmod +x "$fixture/input/"*
            repo=$fixture/repo; here=$fixture/output
            require_root() { :; }; require_tools() { :; }; lock_environment() { :; }
            nsx() { printf '2\\n2\\n3\\n'; }
            ip() { echo 'mock ip'; }; tcpdump() { echo 'mock tcpdump'; }
            run_case() {
                [[ $bin == "$fixture/executable evidence/"*/bin ]]
                test -x "$bin/mcsend"
                igmp_join_runs=4
            }
            main "$fixture/input" "$fixture/executable evidence"
            test -f "$out"
            test "$environment_cleaned" -eq 1
            grep -q 'Executable provenance' "$out"
            grep -q 'source revision unknown' "$out"
        ''', {'tool': '#!/bin/sh\nexit 0\n'})
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
            result = run_shell(['-c',
                                'source "$1"; lock_environment() { :; }; main down',
                                'fixture', str(ENV)], env=environment)
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
