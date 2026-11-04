#!/usr/bin/env python3
"""
refactor.py — Interactive IaC fix loop.

Loads a completed audit or review (produced by audit.py or review.py) and
walks through each failed finding, presenting a file edit for each one.
For each finding the Agent reads the output and takes one of three actions:

  [a]pply   — Agent applies the edit to the IaC file
  [s]kip    — mark as skipped and continue to the next finding
  [d]iscuss — pause so the Agent and user can discuss; resumes on next run

Finding status is persisted back to the audit JSON after every decision.

The interactive loop only runs when stdin is a TTY.  Without a TTY (Junie,
CI) the tool lists pending findings read-only; mutations require explicit
flags (--apply ID..., --skip ID..., --skip-all), optionally with --dry-run.

Usage:
    refactor.py [-l] [<audit_id>] [--apply ID... | --skip ID... | --skip-all] [--dry-run]
"""

import argparse
import json
import sys
from pathlib import Path


AUDITS_ROOT = Path('.audits')

STATUS_FAIL = 'fail'
STATUS_APPLIED = 'applied'
STATUS_SKIPPED = 'skipped'

DISCUSS_MARKER = '--- DISCUSS ---'
SEPARATOR = '=' * 60


# ---------------------------------------------------------------------------
# Audit directory helpers (shared logic with remediate.py)
# ---------------------------------------------------------------------------

def list_audits():
    """List all audit directories sorted newest-first with finding counts."""
    if not AUDITS_ROOT.exists():
        print('No audits found. Run /sectool audit or /sectool review first.')
        return

    dirs = sorted(
        [d for d in AUDITS_ROOT.iterdir() if d.is_dir()],
        key=lambda d: d.name,
        reverse=True,
    )

    if not dirs:
        print('No audits found. Run /sectool audit or /sectool review first.')
        return

    print(f'{"Audit ID":<30} {"Total":>6} {"Fail":>6} {"Applied":>8} {"Skipped":>8}')
    print('-' * 62)
    for d in dirs:
        total = fail = applied = skipped = 0
        for jf in d.glob('*.json'):
            try:
                data = json.loads(jf.read_text())
                for finding in data.get('findings', []):
                    total += 1
                    s = finding.get('status', '')
                    if s == STATUS_FAIL:
                        fail += 1
                    elif s == STATUS_APPLIED:
                        applied += 1
                    elif s == STATUS_SKIPPED:
                        skipped += 1
            except (json.JSONDecodeError, OSError):
                pass
        print(f'{d.name:<30} {total:>6} {fail:>6} {applied:>8} {skipped:>8}')


def resolve_audit_id(audit_id=None):
    """Return the audit directory to use, defaulting to the most recent."""
    if not AUDITS_ROOT.exists():
        print('ERROR: No .audits/ directory found. Run /sectool audit or review first.', file=sys.stderr)
        sys.exit(1)

    if audit_id:
        audit_dir = AUDITS_ROOT / audit_id
        if not audit_dir.is_dir():
            print(f'ERROR: Audit not found: {audit_id}', file=sys.stderr)
            sys.exit(1)
        return audit_dir

    dirs = sorted(
        [d for d in AUDITS_ROOT.iterdir() if d.is_dir()],
        key=lambda d: d.name,
        reverse=True,
    )
    if not dirs:
        print('ERROR: No audits found. Run /sectool audit or review first.', file=sys.stderr)
        sys.exit(1)
    return dirs[0]


def load_findings(audit_dir):
    """Load all finding files from an audit directory.

    Returns list of (path, data) tuples, sorted by filename.
    """
    finding_files = sorted(audit_dir.glob('*.json'))
    results = []
    for jf in finding_files:
        try:
            data = json.loads(jf.read_text())
            results.append((jf, data))
        except (json.JSONDecodeError, OSError) as e:
            print(f'WARNING: Could not read {jf}: {e}', file=sys.stderr)
    return results


def save_findings(path, data):
    path.write_text(json.dumps(data, indent=2))


def collect_pending(all_files):
    """Return [(path, data, index, finding, subsystem)] for every finding still in 'fail' status."""
    pending = []
    for jf, data in all_files:
        subsystem = data.get('subsystem', 'unknown')
        for i, finding in enumerate(data.get('findings', [])):
            if finding.get('status') == STATUS_FAIL:
                pending.append((jf, data, i, finding, subsystem))
    return pending


# ---------------------------------------------------------------------------
# Finding presentation
# ---------------------------------------------------------------------------

def print_finding(index, total, finding, subsystem):
    severity = finding.get('severity', 'UNKNOWN')
    title = finding.get('title', '(no title)')
    detail = finding.get('detail', '')
    check_cmd = finding.get('check_cmd', '')
    remediation = finding.get('remediation', '')

    print(SEPARATOR)
    print(f'Finding {index}/{total}  [{severity}]  subsystem: {subsystem}')
    print(f'Title      : {title}')
    print(f'Detail     : {detail}')
    if check_cmd:
        print(f'Location   : {check_cmd}')
    if remediation:
        print(f'Fix        : {remediation}')
    print()
    print('Action: [a]pply  [s]kip  [d]iscuss')


# ---------------------------------------------------------------------------
# Interactive loop
# ---------------------------------------------------------------------------

def run_refactor(audit_dir):
    all_files = load_findings(audit_dir)
    if not all_files:
        print('No finding files found in audit directory.')
        return

    pending = collect_pending(all_files)

    if not pending:
        print('No failed findings to refactor.')
        return

    total = len(pending)
    applied_count = 0
    skipped_count = 0

    print(f'Audit    : {audit_dir.name}')
    print(f'Findings : {total} failed finding(s) to process')
    print()

    for idx, (jf, data, finding_idx, finding, subsystem) in enumerate(pending, start=1):
        print_finding(idx, total, finding, subsystem)

        # Read decision from stdin (Agent reads prompt output and writes choice)
        try:
            choice = input('> ').strip().lower()
        except EOFError:
            choice = 's'

        if choice in ('a', 'apply'):
            data['findings'][finding_idx]['status'] = STATUS_APPLIED
            save_findings(jf, data)
            applied_count += 1
            print(f'APPLY: {finding.get("remediation", "")}')
            print()

        elif choice in ('d', 'discuss'):
            print()
            print(DISCUSS_MARKER)
            print(f'Finding   : {finding.get("title", "")}')
            print(f'Detail    : {finding.get("detail", "")}')
            print(f'Location  : {finding.get("check_cmd", "")}')
            print(f'Fix       : {finding.get("remediation", "")}')
            print(DISCUSS_MARKER)
            # Remaining findings are preserved; exit so Agent can converse
            remaining = total - idx
            if remaining > 0:
                print(f'{remaining} finding(s) remain. Re-run /sectool refactor {audit_dir.name} to continue.')
            break

        else:
            # Default: skip
            data['findings'][finding_idx]['status'] = STATUS_SKIPPED
            save_findings(jf, data)
            skipped_count += 1
            print('Skipped.')
            print()

    else:
        # Loop completed without discuss break
        print(SEPARATOR)
        print(f'Done. Applied: {applied_count}  Skipped: {skipped_count}')


# ---------------------------------------------------------------------------
# Non-interactive mode (no TTY / explicit flags)
# ---------------------------------------------------------------------------

def list_pending(audit_dir):
    """Read-only table of pending findings; never writes."""
    pending = collect_pending(load_findings(audit_dir))
    print(f'Audit    : {audit_dir.name}')
    print(f'Pending  : {len(pending)} failed finding(s)')
    if not pending:
        return 0
    print()
    print(f'{"ID":<28} {"Severity":<9} {"Subsystem":<10} Title')
    print('-' * 80)
    for _, _, _, finding, subsystem in pending:
        print(f'{finding.get("id", "?"):<28} {finding.get("severity", "?"):<9} {subsystem:<10} {finding.get("title", "")}')
        if finding.get('check_cmd'):
            print(f'{"":<28} at : {finding["check_cmd"]}')
        if finding.get('remediation'):
            print(f'{"":<28} fix: {finding["remediation"]}')
    print()
    print(f'Decide with: sectool refactor {audit_dir.name} --apply ID... | --skip ID... | --skip-all [--dry-run]')
    return 0


def apply_decisions(audit_dir, args):
    """Set finding status by ID per --apply/--skip/--skip-all; --dry-run previews only."""
    pending = collect_pending(load_findings(audit_dir))
    if args.skip_all:
        selected = pending
        new_status = STATUS_SKIPPED
        wanted = [f.get('id') for _, _, _, f, _ in pending]
    else:
        wanted = args.apply or args.skip
        new_status = STATUS_APPLIED if args.apply else STATUS_SKIPPED
        by_id = {entry[3].get('id'): entry for entry in pending}
        unknown = [fid for fid in wanted if fid not in by_id]
        if unknown:
            print(f'ERROR: Unknown or non-pending finding ID(s): {", ".join(unknown)}', file=sys.stderr)
            print(f'Run: sectool refactor {audit_dir.name} (lists pending IDs)', file=sys.stderr)
            return 1
        selected = [by_id[fid] for fid in wanted]

    if not selected:
        print('No failed findings to refactor.')
        return 0

    prefix = 'DRY-RUN ' if args.dry_run else ''
    touched = {}
    for jf, data, idx, finding, _ in selected:
        print(f'{prefix}{new_status.upper():<8} {finding.get("id", "?")}  {finding.get("title", "")}')
        if new_status == STATUS_APPLIED and finding.get('remediation'):
            print(f'         fix: {finding["remediation"]}')
        if not args.dry_run:
            data['findings'][idx]['status'] = new_status
            touched[jf] = data
    for jf, data in touched.items():
        save_findings(jf, data)
    print()
    print(f'{prefix}{new_status}: {len(selected)} of {len(wanted)} requested finding(s)')
    return 0


# ---------------------------------------------------------------------------
# Summary helper
# ---------------------------------------------------------------------------

def print_final_summary(audit_dir):
    all_files = load_findings(audit_dir)
    counts = {STATUS_FAIL: 0, STATUS_APPLIED: 0, STATUS_SKIPPED: 0}
    for _, data in all_files:
        for finding in data.get('findings', []):
            s = finding.get('status', '')
            if s in counts:
                counts[s] += 1
    print()
    print(f'Audit summary — {audit_dir.name}')
    print(f'  Remaining (fail) : {counts[STATUS_FAIL]}')
    print(f'  Applied          : {counts[STATUS_APPLIED]}')
    print(f'  Skipped          : {counts[STATUS_SKIPPED]}')


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def parse_args(argv=None):
    p = argparse.ArgumentParser(
        prog='sectool refactor',
        description='Walk failed audit/review findings and record apply/skip decisions for IaC fixes. '
                    'Interactive only on a TTY; otherwise lists pending findings read-only.',
    )
    p.add_argument('audit_id', nargs='?', help='audit directory under .audits/ (default: newest)')
    p.add_argument('-l', '--list-audits', action='store_true', help='list audits with finding counts and exit')
    g = p.add_mutually_exclusive_group()
    g.add_argument('--apply', nargs='+', metavar='ID', help='mark finding ID(s) as applied')
    g.add_argument('--skip', nargs='+', metavar='ID', help='mark finding ID(s) as skipped')
    g.add_argument('--skip-all', action='store_true', help='mark every pending finding as skipped')
    p.add_argument('--dry-run', action='store_true', help='preview decisions without writing')
    p.add_argument('--check-args', action='store_true', help='parse arguments, print them as JSON and exit')
    return p.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    if args.check_args:
        print(json.dumps(vars(args)))
        return 0
    if args.list_audits:
        list_audits()
        return 0

    audit_dir = resolve_audit_id(args.audit_id)
    if args.apply or args.skip or args.skip_all:
        rc = apply_decisions(audit_dir, args)
        if rc == 0 and not args.dry_run:
            print_final_summary(audit_dir)
        return rc
    if not sys.stdin.isatty():
        return list_pending(audit_dir)

    run_refactor(audit_dir)
    print_final_summary(audit_dir)
    return 0


if __name__ == '__main__':
    sys.exit(main())
