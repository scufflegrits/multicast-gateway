#!/usr/bin/env python3
"""Check local documentation links, Markdown fences and Mermaid init structure.

This does not render Mermaid or validate its full grammar/appearance, and it
is not a complete Markdown parser.
"""
from pathlib import Path
from urllib.parse import unquote
import json
import re
import sys

# CommonMark fences: up to three spaces of indentation, then at least three
# backticks or tildes. A backtick fence's info string cannot contain backticks.
FENCE_OPEN = re.compile(r'^ {0,3}(`{3,}|~{3,})(.*)$')


def scan_fences(text):
    """Split text into prose lines and fenced blocks.

    Returns (prose_lines, blocks, unclosed) where blocks are (info, body) pairs.
    """
    prose, blocks = [], []
    fence = info = None
    body = []
    for line in text.splitlines():
        if fence is None:
            match = FENCE_OPEN.match(line)
            if match and not (match[1][0] == '`' and '`' in match[2]):
                fence, info, body = match[1], match[2].strip(), []
            else:
                prose.append(line)
            continue
        closing = re.match(r'^ {0,3}(`{3,}|~{3,})\s*$', line)
        if closing and closing[1][0] == fence[0] and len(closing[1]) >= len(fence):
            blocks.append((info, '\n'.join(body)))
            fence = None
        else:
            body.append(line)
    return prose, blocks, fence is not None


def headings(text):
    result = set()
    counts = {}
    for line in scan_fences(text)[0]:
        match = re.match(r'^#{1,6} (.+)$', line)
        if match:
            slug = re.sub(r'[^\w\- ]', '', match[1].replace('`', '').lower()).replace(' ', '-')
            count = counts.get(slug, 0)
            counts[slug] = count + 1
            result.add(slug if not count else f'{slug}-{count}')
    return result


def check(root):
    files = [root / 'README.md',
             *(path for top in ('docs', 'test', 'prototypes') for path in sorted((root / top).rglob('*.md')))]
    errors = []
    for path in files:
        text = path.read_text(encoding='utf-8')
        label = path.relative_to(root)
        prose, blocks, unclosed = scan_fences(text)
        if unclosed:
            errors.append(f'{label}: unbalanced fenced blocks')
        # Current docs use simple inline local Markdown links, with no title syntax.
        for target, fragment in re.findall(r'\]\(([^)#]*)(?:#([^)]*))?\)', '\n'.join(prose)):
            if re.match(r'\w+://|mailto:', target):
                continue
            target, fragment = unquote(target), unquote(fragment)
            linked = (path.parent / target).resolve() if target else path
            if not linked.is_file():
                errors.append(f'{label}: missing file {target}')
            elif fragment and fragment not in headings(linked.read_text(encoding='utf-8')):
                errors.append(f'{label}: missing heading {target}#{fragment}')
        diagrams = [body for info, body in blocks if info.split()[:1] == ['mermaid']]
        for index, block in enumerate(diagrams, 1):
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
    return files, errors


if __name__ == '__main__':
    files, errors = check(Path(__file__).resolve().parents[1])
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        sys.exit(1)
    print(f'Checked {len(files)} documents: local links, fences, Mermaid init/direction/colors/subgraphs.')
    print('Visual rendering and full Mermaid grammar remain unverified.')
