#!/usr/bin/env python3
"""Lightweight tests for histmgr (run: python3 test_histmgr.py)."""

from __future__ import annotations

import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import histmgr as hm


class HistmgrUnit(unittest.TestCase):
    def test_safe_session_dir_rejects_escape(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            self.assertIsNone(hm._safe_session_dir(root, '../etc'))
            self.assertIsNone(hm._safe_session_dir(root, 'a/b'))
            self.assertIsNone(hm._safe_session_dir(root, ''))
            p = hm._safe_session_dir(root, 'session-abc')
            self.assertIsNotNone(p)
            assert p is not None
            self.assertEqual(p, (root / 'session-abc').resolve())

    def test_apply_filters_since_until_and_query(self) -> None:
        rows = [
            hm.SessionRow('a', 'todo work', '/p/isen', 'finished', 1_700_000_000_000, 1_700_000_000_000, 5000, None),
            hm.SessionRow('b', 'other', '/p/other', 'finished', 1_600_000_000_000, 1_600_000_000_000, 100, None),
        ]
        # force timestamps: use ms for 2023-11-14-ish
        rows[0].updated_at = int(hm._parse_day_ms('2024-06-01'))
        rows[1].updated_at = int(hm._parse_day_ms('2023-01-01'))
        out = hm.apply_filters(rows, project='isen')
        self.assertEqual([r.session_id for r in out], ['a'])
        out = hm.apply_filters(rows, query='todo')
        self.assertEqual([r.session_id for r in out], ['a'])
        out = hm.apply_filters(rows, since='2024-01-01')
        self.assertEqual([r.session_id for r in out], ['a'])
        out = hm.apply_filters(rows, until='2023-12-31')
        self.assertEqual([r.session_id for r in out], ['b'])

    def test_invalid_query_exits(self) -> None:
        with self.assertRaises(SystemExit):
            hm._compile_query('(')

    def test_mine_candidates_counts(self) -> None:
        rows = [
            hm.SessionRow(
                's1',
                'implement todo-a1b2c3d4 from trackers/todo',
                '/x',
                None,
                None,
                None,
                0,
                None,
            ),
            hm.SessionRow(
                's2',
                'fix the build errors clion-Build log ninja: error',
                '/x',
                None,
                None,
                None,
                0,
                None,
            ),
        ]
        c = hm.mine_candidates(rows)
        ids = {x['id']: x['count'] for x in c}
        self.assertGreaterEqual(ids.get('todo_implement', 0), 1)
        self.assertGreaterEqual(ids.get('fix_from_logs', 0), 1)

    def test_delete_protects_current(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            home = Path(td)
            sess = home / 'sessions' / 'session-live'
            sess.mkdir(parents=True)
            (sess / 'transcript.md').write_text('hi', encoding='utf-8')
            other = home / 'sessions' / 'session-old'
            other.mkdir(parents=True)
            (other / 'transcript.md').write_text('old', encoding='utf-8')
            idx = home / 'sessions' / 'index.jsonl'
            idx.write_text(
                json.dumps({'sessionId': 'session-live'})
                + '\n'
                + json.dumps({'sessionId': 'session-old'})
                + '\n',
                encoding='utf-8',
            )

            with mock.patch.dict(os.environ, {'JUNIE_HOME': str(home), 'JUNIE_SESSION_ID': 'session-live'}):
                ns = hm.build_parser().parse_args(
                    ['delete', 'session-live', 'session-old', '--yes', '--dry-run']
                )
                # dry-run still lists after protection filter
                rc = hm.cmd_delete(ns)
                self.assertEqual(rc, 0)

            with mock.patch.dict(os.environ, {'JUNIE_HOME': str(home), 'JUNIE_SESSION_ID': 'session-live'}):
                ns = hm.build_parser().parse_args(['delete', 'session-live', 'session-old', '--yes'])
                rc = hm.cmd_delete(ns)
                self.assertEqual(rc, 0)
                self.assertTrue(sess.is_dir(), 'live session must remain')
                self.assertFalse(other.is_dir(), 'old session should be removed')

    def test_annotate_existence(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            home = Path(td)
            (home / 'skills' / 'dev-project-todo-implement').mkdir(parents=True)
            (home / 'commands').mkdir(parents=True)
            (home / 'commands' / 'histmgr.md').write_text('x', encoding='utf-8')
            with mock.patch.dict(os.environ, {'JUNIE_HOME': str(home)}):
                cands = [
                    {'suggested_name': 'dev-project-todo-implement', 'kind': 'skill'},
                    {'suggested_name': 'histmgr', 'kind': 'command'},
                    {'suggested_name': 'missing-skill', 'kind': 'skill'},
                ]
                hm.annotate_existence(cands)
                self.assertTrue(cands[0]['already_exists'])
                self.assertTrue(cands[1]['already_exists'])
                self.assertFalse(cands[2]['already_exists'])


    def test_check_args_touches_no_sessions(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            missing = str(Path(td) / 'no-such-home')
            with mock.patch.dict(os.environ, {'JUNIE_HOME': missing}):
                with mock.patch('sys.stdout', new_callable=io.StringIO) as out:
                    rc = hm.main(['--check-args', 'list', '-p', 'x', '-n', '5'])
                self.assertEqual(rc, 0)
                ns = json.loads(out.getvalue())
                self.assertEqual((ns['cmd'], ns['project'], ns['limit']), ('list', 'x', 5))
                self.assertNotIn('func', ns)
                with mock.patch('sys.stdout', new_callable=io.StringIO) as out:
                    self.assertEqual(hm.main(['--check-args']), 0)
                self.assertEqual(json.loads(out.getvalue())['cmd'], 'mine')
                with self.assertRaises(SystemExit) as cm:
                    hm.main(['--check-args', 'list', '--bogus'])
                self.assertEqual(cm.exception.code, 2)
            self.assertFalse(Path(missing).exists())

    def test_tag_filter(self) -> None:
        rows = [
            hm.SessionRow('a', 'implement todo-deadbeef trackers/todo', '/p', None, None, None, 0, None),
            hm.SessionRow('b', 'refactor terraform module', '/p', None, None, None, 0, None),
        ]
        out = hm.apply_filters(rows, tag='todo_implement')
        self.assertEqual([r.session_id for r in out], ['a'])
        out = hm.apply_filters(rows, tag='terraform')
        self.assertEqual([r.session_id for r in out], ['b'])


if __name__ == '__main__':
    unittest.main()
