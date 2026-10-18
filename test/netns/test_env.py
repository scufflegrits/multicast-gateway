#!/usr/bin/env python3
"""Check namespace enumeration with mocks; no root or networking is required."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ENV = Path(__file__).with_name('env.sh')


class EnumerationTests(unittest.TestCase):
    def run_environment(self, command, listing):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            mocks = {
                'id': '#!/bin/sh\nprintf "0\\n"\n',
                'sysctl': '#!/bin/sh\nexit 0\n',
                'ip': '''#!/bin/sh
printf '%s\\n' "$*" >> "$MOCK_LOG"
if [ "$1 $2" = 'netns list' ]; then
    case "$MOCK_LISTING" in
        failure) exit 8 ;;
        existing) printf 'mcgw-gw (id: 0)\\n' ;;
    esac
fi
''',
            }
            for name, contents in mocks.items():
                target = path / name
                target.write_text(contents)
                target.chmod(0o755)
            log = path / 'commands'
            environment = {**os.environ, 'PATH': directory + ':' + os.environ['PATH'],
                           'MOCK_LOG': str(log), 'MOCK_LISTING': listing}
            result = subprocess.run(['bash', '-c',
                                     'source "$1"; lock_environment() { :; }; main "$2"',
                                     'fixture', str(ENV), command], env=environment,
                                    capture_output=True, text=True, timeout=5)
            return result, log.read_text().splitlines()

    def test_failed_listing_prevents_creation_and_absence_claims(self):
        for command in ('up', 'status'):
            with self.subTest(command=command):
                result, commands = self.run_environment(command, 'failure')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(commands, ['netns list'])
                self.assertNotIn('ENV up', result.stdout)
                self.assertNotIn('ENV not present', result.stdout)

    def test_empty_listing_allows_creation(self):
        result, commands = self.run_environment('up', 'empty')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ENV up', result.stdout)
        self.assertEqual(sum(line.startswith('netns add ') for line in commands), 7)

    def test_existing_environment_prevents_creation(self):
        result, commands = self.run_environment('up', 'existing')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('namespaces already exist', result.stderr)
        self.assertEqual(commands, ['netns list'])

    def test_status_uses_one_successful_snapshot(self):
        for listing, expected in [('empty', 'ENV not present'), ('existing', '== mcgw-gw')]:
            with self.subTest(listing=listing):
                result, commands = self.run_environment('status', listing)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(expected, result.stdout)
                self.assertEqual(commands.count('netns list'), 1)


if __name__ == '__main__':
    unittest.main()
