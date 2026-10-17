#!/usr/bin/env python3
"""Regression fixtures for check-docs.py, run in temporary repositories.

Run: python3 scripts/test_check_docs.py
"""
from pathlib import Path
import importlib.util
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('check_docs', Path(__file__).with_name('check-docs.py'))
check_docs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_docs)

INIT = '%%{init: {"theme":"base"}}%%'


def run(files):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / 'docs').mkdir()
        (root / 'README.md').write_text('# Readme\n', encoding='utf-8')
        for name, text in files.items():
            (root / name).write_text(text, encoding='utf-8')
        return check_docs.check(root)[1]


class CheckDocsTest(unittest.TestCase):
    def test_unclosed_indented_fence(self):
        errors = run({'docs/a.md': 'Text\n\n   ```\ncode\n'})
        self.assertIn('docs/a.md: unbalanced fenced blocks', errors)

    def test_link_inside_tilde_fence_ignored(self):
        self.assertEqual(run({'docs/a.md': '~~~\n[x](missing.md)\n~~~\n'}), [])

    def test_tilde_mermaid_checked(self):
        errors = run({'docs/a.md': '~~~mermaid\nflowchart LR\n~~~\n'})
        self.assertIn('docs/a.md: diagram 1: missing init', errors)
        self.assertIn('docs/a.md: diagram 1: expected TB flowchart', errors)

    def test_valid_tilde_mermaid(self):
        self.assertEqual(run({'docs/a.md': f'~~~mermaid\n{INIT}\nflowchart TB\n~~~\n'}), [])

    def test_shorter_or_other_fence_does_not_close(self):
        text = '````\n```\n[x](missing.md)\n~~~~\n````\n'
        self.assertEqual(run({'docs/a.md': text}), [])

    def test_four_space_indent_is_not_a_fence(self):
        self.assertEqual(run({'docs/a.md': 'Text\n\n    ```\n'}), [])

    def test_percent_encoded_link(self):
        files = {'docs/with space.md': '# Target heading\n',
                 'docs/a.md': '[x](with%20space.md#target-heading)\n'}
        self.assertEqual(run(files), [])

    def test_missing_heading_reported(self):
        files = {'docs/b.md': '# Real\n', 'docs/a.md': '[x](b.md#absent)\n'}
        self.assertIn('docs/a.md: missing heading b.md#absent', run(files))


if __name__ == '__main__':
    unittest.main()
