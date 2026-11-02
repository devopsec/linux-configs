#!/usr/bin/env python3
"""Lightweight tests for sectools (run: python3 test_sectools.py)."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SECTOOL = HERE / 'sectool.py'
AUDIT_ID = '20260101-000000-review'


def _fixture(root: Path) -> Path:
    audit_dir = root / '.audits' / AUDIT_ID
    audit_dir.mkdir(parents=True)
    data = {
        'audit_id': AUDIT_ID,
        'platform': 'gcp',
        'subsystem': 'iam',
        'timestamp': '2026-01-01T00:00:00Z',
        'findings': [
            {'id': 'gcp-iam-001', 'severity': 'CRITICAL', 'title': 'Primitive role', 'detail': 'd',
             'check_cmd': 'main.tf:3', 'remediation': 'use predefined role', 'status': 'fail'},
            {'id': 'gcp-iam-002', 'severity': 'HIGH', 'title': 'SA key', 'detail': 'd',
             'check_cmd': 'main.tf:9', 'remediation': 'remove key', 'status': 'fail'},
            {'id': 'gcp-iam-003', 'severity': 'INFO', 'title': 'ok', 'detail': 'No issues found',
             'check_cmd': '', 'remediation': '', 'status': 'pass'},
        ],
    }
    (audit_dir / 'gcp-iam.json').write_text(json.dumps(data, indent=2), encoding='utf-8')
    return audit_dir / 'gcp-iam.json'


def _statuses(path: Path) -> dict[str, str]:
    data = json.loads(path.read_text(encoding='utf-8'))
    return {f['id']: f['status'] for f in data['findings']}


def _run(args: list[str], cwd: Path, script: Path = SECTOOL) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(script), *args],
        cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True, text=True, check=False, timeout=30,
    )


class DispatcherTests(unittest.TestCase):
    def test_bare_lists_tools(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            proc = _run([], Path(td))
        self.assertEqual(proc.returncode, 0)
        self.assertIn('sectool — security tools', proc.stdout)
        self.assertIn('--check-args', proc.stdout)

    def test_unknown_tool_exits_2(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            proc = _run(['nope'], Path(td))
        self.assertEqual(proc.returncode, 2)

    def test_check_args_forwarded(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            ok = _run(['--check-args', 'review', '-s', 'iam', 'network'], Path(td))
            bad = _run(['--check-args', 'review', '/bad/path'], Path(td))
            audit = _run(['--check-args', 'audit'], Path(td))
            rem = _run(['--check-args', 'remediate', '--skip', 'x', '--dry-run'], Path(td))
            self.assertFalse((Path(td) / '.audits').exists(), 'check-args must not write')
        self.assertEqual(ok.returncode, 0, ok.stderr)
        self.assertEqual(json.loads(ok.stdout)['subsystems'], ['iam', 'network'])
        self.assertEqual(bad.returncode, 2)
        self.assertEqual(audit.returncode, 0, audit.stderr)
        self.assertEqual(rem.returncode, 0, rem.stderr)
        self.assertTrue(json.loads(rem.stdout)['dry_run'])


class NonInteractiveTests(unittest.TestCase):
    def test_help_without_audits(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            for tool in ('remediate', 'refactor'):
                proc = _run([tool, '--help'], Path(td))
                self.assertEqual(proc.returncode, 0, proc.stderr)
                self.assertIn('--apply', proc.stdout)
                bare = _run([tool], Path(td))
                self.assertEqual(bare.returncode, 0, bare.stderr)

    def test_no_tty_lists_without_mutation(self) -> None:
        for tool in ('remediate', 'refactor'):
            with self.subTest(tool=tool), tempfile.TemporaryDirectory() as td:
                jf = _fixture(Path(td))
                before = jf.read_text(encoding='utf-8')
                proc = _run([tool, AUDIT_ID], Path(td))
                self.assertEqual(proc.returncode, 0, proc.stderr)
                self.assertIn('gcp-iam-001', proc.stdout)
                self.assertIn('gcp-iam-002', proc.stdout)
                self.assertNotIn('gcp-iam-003', proc.stdout)
                self.assertEqual(jf.read_text(encoding='utf-8'), before)

    def test_default_audit_is_newest(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            _fixture(Path(td))
            older = Path(td) / '.audits' / '20250101-000000-audit'
            older.mkdir()
            proc = _run([], Path(td), script=HERE / 'remediate.py')
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(AUDIT_ID, proc.stdout)
        self.assertIn('Pending  : 2', proc.stdout)

    def test_list_audits_flag(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            _fixture(Path(td))
            proc = _run(['refactor', '-l'], Path(td))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(AUDIT_ID, proc.stdout)

    def test_dry_run_does_not_write(self) -> None:
        for tool in ('remediate', 'refactor'):
            with self.subTest(tool=tool), tempfile.TemporaryDirectory() as td:
                jf = _fixture(Path(td))
                proc = _run([tool, AUDIT_ID, '--skip', 'gcp-iam-001', '--dry-run'], Path(td))
                self.assertEqual(proc.returncode, 0, proc.stderr)
                self.assertIn('DRY-RUN', proc.stdout)
                self.assertEqual(_statuses(jf)['gcp-iam-001'], 'fail')

    def test_apply_marks_only_selected(self) -> None:
        for tool in ('remediate', 'refactor'):
            with self.subTest(tool=tool), tempfile.TemporaryDirectory() as td:
                jf = _fixture(Path(td))
                proc = _run([tool, AUDIT_ID, '--apply', 'gcp-iam-002'], Path(td))
                self.assertEqual(proc.returncode, 0, proc.stderr)
                self.assertEqual(
                    _statuses(jf),
                    {'gcp-iam-001': 'fail', 'gcp-iam-002': 'applied', 'gcp-iam-003': 'pass'},
                )

    def test_skip_all_then_empty(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            jf = _fixture(Path(td))
            proc = _run(['refactor', AUDIT_ID, '--skip-all'], Path(td))
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(
                _statuses(jf),
                {'gcp-iam-001': 'skipped', 'gcp-iam-002': 'skipped', 'gcp-iam-003': 'pass'},
            )
            mtime = jf.stat().st_mtime_ns
            again = _run(['refactor', AUDIT_ID, '--skip-all'], Path(td))
            self.assertEqual(again.returncode, 0, again.stderr)
            self.assertIn('No failed findings', again.stdout)
            self.assertEqual(jf.stat().st_mtime_ns, mtime)

    def test_unknown_id_exits_1_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            jf = _fixture(Path(td))
            before = jf.read_text(encoding='utf-8')
            proc = _run(['remediate', AUDIT_ID, '--apply', 'gcp-iam-001', 'gcp-iam-999'], Path(td))
            self.assertEqual(proc.returncode, 1)
            self.assertIn('gcp-iam-999', proc.stderr)
            self.assertEqual(jf.read_text(encoding='utf-8'), before)

    def test_apply_and_skip_are_exclusive(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            _fixture(Path(td))
            proc = _run(['remediate', AUDIT_ID, '--apply', 'a', '--skip', 'b'], Path(td))
        self.assertEqual(proc.returncode, 2)

    def test_missing_audit_id_exits_1(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            _fixture(Path(td))
            proc = _run(['remediate', 'does-not-exist'], Path(td))
        self.assertEqual(proc.returncode, 1)
        self.assertIn('Audit not found', proc.stderr)


if __name__ == '__main__':
    unittest.main()
