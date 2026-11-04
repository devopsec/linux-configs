#!/usr/bin/env python3
"""sectool — dispatcher for ~/.junie/custom/scripts/sectools/*.py tools."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

TOOLS = ('audit', 'review', 'remediate', 'refactor')
_HERE = Path(__file__).resolve().parent


def _tool_path(name: str) -> Path:
    return _HERE / f'{name}.py'


def _list_tools() -> int:
    print('sectool — security tools')
    print()
    hdr = f'{"tool":12} {"script":24} purpose'
    print(hdr)
    print(f'{"-" * 12} {"-" * 24} {"-" * 40}')
    purposes = {
        'audit': 'Live GCP / environment security scan',
        'review': 'Code/config security review',
        'remediate': 'Apply security remediations (explicit approval)',
        'refactor': 'Security-oriented refactoring suggestions/edits',
    }
    for name in TOOLS:
        path = _tool_path(name)
        mark = 'ok' if path.is_file() else 'MISSING'
        print(f'{name:12} {path.name:24} [{mark}] {purposes.get(name, "")}')
    print()
    print('Usage:')
    print('  sectool                            # list tools (this help)')
    print('  sectool <tool> --help              # tool help')
    print('  sectool <tool> [args...]           # run tool (cwd = IaC repo root; writes .audits/<id>/)')
    print('  sectool --check-args <tool> [args] # parse-only: validate args, no side effects')
    print()
    print('Examples:')
    print('  sectool review -s iam network      # static IaC scan of ./platforms/*.tf')
    print('  sectool refactor -l                # list audits/reviews with finding counts')
    print('  sectool audit -s iam               # LIVE GCP scan — needs gcloud auth + user OK')
    return 0


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    check_args = False
    if args and args[0] == '--check-args':
        check_args = True
        args = args[1:]
    if not args or args[0] in ('-h', '--help', 'help', 'list'):
        return _list_tools()
    tool = args[0]
    rest = args[1:]
    if tool not in TOOLS:
        print(f'unknown tool: {tool!r} (expected one of: {", ".join(TOOLS)})', file=sys.stderr)
        _list_tools()
        return 2
    script = _tool_path(tool)
    if not script.is_file():
        print(f'missing script: {script}', file=sys.stderr)
        return 1
    # If only the tool name was given, prefer --help so bare /sectool review is useful.
    if not rest and not check_args:
        rest = ['--help']
    if check_args:
        rest = ['--check-args', *rest]
    proc = subprocess.run([sys.executable, str(script), *rest], check=False)
    return int(proc.returncode or 0)


if __name__ == '__main__':
    raise SystemExit(main())
