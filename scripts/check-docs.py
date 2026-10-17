#!/usr/bin/env python3
"""Check local documentation links, Markdown fences and Mermaid init structure.

This does not render Mermaid or validate its full grammar/appearance.
"""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FILES = [ROOT / 'README.md', *sorted((ROOT / 'docs').glob('*.md'))]
errors = []

def headings(text):
    result = set()
    counts = {}
    in_fence = False
    for line in text.splitlines():
        if line.startswith('```'):
            in_fence = not in_fence
        if in_fence:
            continue
        match = re.match(r'^#{1,6} (.+)$', line)
        if match:
            slug = re.sub(r'[^\w\- ]', '', match[1].lower()).replace(' ', '-')
            count = counts.get(slug, 0)
            counts[slug] = count + 1
            result.add(slug if not count else f'{slug}-{count}')
    return result

for path in FILES:
    text = path.read_text()
    label = path.relative_to(ROOT)
    if sum(line.startswith('```') for line in text.splitlines()) % 2:
        errors.append(f'{label}: unbalanced fenced blocks')
    # Current docs use simple inline local Markdown links, with no title syntax.
    for target, fragment in re.findall(r'\]\(([^)#]*)(?:#([^)]*))?\)', text):
        if re.match(r'\w+://|mailto:', target):
            continue
        linked = (path.parent / target).resolve() if target else path
        if not linked.is_file():
            errors.append(f'{label}: missing file {target}')
        elif fragment and fragment not in headings(linked.read_text()):
            errors.append(f'{label}: missing heading {target}#{fragment}')
    for index, block in enumerate(re.findall(r'```mermaid\n(.*?)```', text, re.S), 1):
        init = re.search(r'%%\{init: (.*?)\}%%', block)
        try:
            if not init:
                raise ValueError('missing init')
            json.loads(init[1])
        except (ValueError, json.JSONDecodeError) as exc:
            errors.append(f'{label}: diagram {index}: {exc}')
        if 'flowchart TB' not in block:
            errors.append(f'{label}: diagram {index}: expected TB flowchart')
        if re.search(r'#[0-9a-fA-F]{3,8}\b', block):
            errors.append(f'{label}: diagram {index}: expected CSS named colors')
        nesting = 0
        for line in block.splitlines():
            if line.strip().startswith('subgraph '):
                nesting += 1
            elif line.strip() == 'end':
                nesting -= 1
            if nesting < 0:
                break
        if nesting:
            errors.append(f'{label}: diagram {index}: unbalanced subgraphs')

if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print(f'Checked {len(FILES)} documents: local links, fences, Mermaid init/direction/colors/subgraphs.')
print('Visual rendering and full Mermaid grammar remain unverified.')
