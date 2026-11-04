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

            with mock.patch.dict(os.environ, {'JUNIE_HOME': str(home), 'JUNIE_SESSION_ID': 'session-live', 'AGENT_TARGET': 'junie'}):
                ns = hm.build_parser().parse_args(
                    ['delete', 'session-live', 'session-old', '--yes', '--dry-run']
                )
                # dry-run still lists after protection filter
                rc = hm.cmd_delete(ns)
                self.assertEqual(rc, 0)

            with mock.patch.dict(os.environ, {'JUNIE_HOME': str(home), 'JUNIE_SESSION_ID': 'session-live', 'AGENT_TARGET': 'junie'}):
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
            with mock.patch.dict(os.environ, {'JUNIE_HOME': str(home), 'AGENT_TARGET': 'junie'}):
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


def _claude_record(**kw: object) -> str:
    return json.dumps(kw) + '\n'


class ClaudeBackendTests(unittest.TestCase):
    """Claude Code history: projects/<cwd>/<id>.jsonl plus per-session sidecars."""

    def _home(self, td: str) -> Path:
        home = Path(td) / 'claude'
        proj = home / 'projects' / '-tmp-demo'
        proj.mkdir(parents=True)
        (proj / 'memory').mkdir()
        (proj / 'memory' / 'MEMORY.md').write_text('keep', encoding='utf-8')
        for sid, title, prompt in (
            ('11111111-aaaa', 'Fix kamailio pike config', 'tune kamailio pike'),
            ('22222222-bbbb', None, 'implement todo-deadbeef from trackers/todo'),
        ):
            lines = _claude_record(type='user', sessionId=sid, cwd='/tmp/demo', timestamp='2026-10-01T10:00:00Z',
                                   message={'role': 'user', 'content': prompt})
            lines += _claude_record(type='user', isMeta=True, sessionId=sid, timestamp='2026-10-01T10:00:01Z',
                                    message={'role': 'user', 'content': 'meta noise'})
            lines += _claude_record(type='assistant', sessionId=sid, timestamp='2026-10-01T10:00:02Z',
                                    message={'role': 'assistant', 'content': [
                                        {'type': 'thinking', 'thinking': 'hidden'},
                                        {'type': 'text', 'text': 'Done.'},
                                        {'type': 'tool_use', 'name': 'Bash', 'input': {}}]})
            if title:
                lines += _claude_record(type='ai-title', sessionId=sid, aiTitle=title)
            (proj / f'{sid}.jsonl').write_text(lines, encoding='utf-8')
        (proj / '11111111-aaaa' / 'subagents').mkdir(parents=True)
        (home / 'file-history' / '11111111-aaaa').mkdir(parents=True)
        (home / 'session-env' / '11111111-aaaa').mkdir(parents=True)
        return home

    def test_load_rows_and_transcript(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            be = hm.ClaudeBackend(self._home(td))
            rows = {r.session_id: r for r in be.load_rows()}
            self.assertEqual(set(rows), {'11111111-aaaa', '22222222-bbbb'})
            self.assertEqual(rows['11111111-aaaa'].task_name, 'Fix kamailio pike config')
            self.assertEqual(rows['22222222-bbbb'].task_name, 'implement todo-deadbeef from trackers/todo')
            self.assertEqual(rows['11111111-aaaa'].project_dir, '/tmp/demo')
            text = hm.row_text(rows['11111111-aaaa'])
            self.assertIn('tune kamailio pike', text)
            self.assertIn('Done.', text)
            self.assertNotIn('meta noise', text)
            self.assertNotIn('hidden', text)
            self.assertIn('kamailio', hm.detect_tags(rows['11111111-aaaa']))
            self.assertIn('todo_implement', hm.detect_tags(rows['22222222-bbbb']))

    def test_delete_removes_sidecars_keeps_memory_and_live(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            home = self._home(td)
            proj = home / 'projects' / '-tmp-demo'
            env = {'AGENT_TARGET': 'claude', 'CLAUDE_HOME': str(home), 'CLAUDE_CODE_SESSION_ID': '22222222-bbbb'}
            with mock.patch.dict(os.environ, env):
                with mock.patch('sys.stdout', new_callable=io.StringIO):
                    rc = hm.main(['delete', '11111111-aaaa', '22222222-bbbb', '--yes'])
            self.assertEqual(rc, 0)
            self.assertFalse((proj / '11111111-aaaa.jsonl').exists())
            self.assertFalse((proj / '11111111-aaaa').exists())
            self.assertFalse((home / 'file-history' / '11111111-aaaa').exists())
            self.assertFalse((home / 'session-env' / '11111111-aaaa').exists())
            self.assertTrue((proj / '22222222-bbbb.jsonl').exists(), 'live session must remain')
            self.assertTrue((proj / 'memory' / 'MEMORY.md').exists(), 'project memory must remain')

    def test_list_json_via_main(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            home = self._home(td)
            with mock.patch.dict(os.environ, {'CLAUDE_HOME': str(home)}):
                with mock.patch('sys.stdout', new_callable=io.StringIO) as out:
                    rc = hm.main(['--agent', 'claude', 'list', '--json', '-q', 'kamailio'])
            self.assertEqual(rc, 0)
            data = json.loads(out.getvalue())
            self.assertEqual([d['sessionId'] for d in data], ['11111111-aaaa'])
            self.assertEqual(data[0]['agent'], 'claude')


class AgentResolutionTests(unittest.TestCase):
    def test_unresolvable_agent_exits_2(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            env = {'JUNIE_HOME': str(Path(td) / 'j'), 'CLAUDE_HOME': str(Path(td) / 'c')}
            (Path(td) / 'j').mkdir()
            (Path(td) / 'c').mkdir()
            clean = {k: v for k, v in os.environ.items()
                     if k not in ('AGENT_TARGET', 'CLAUDECODE', 'CLAUDE_CODE_SESSION_ID', 'JUNIE_SESSION_ID',
                                  'JUNIE_SESSION', 'JUNIE_CURRENT_SESSION')}
            clean.update(env)
            with mock.patch.dict(os.environ, clean, clear=True):
                with mock.patch('sys.stdin', new_callable=io.StringIO):
                    with mock.patch('sys.stderr', new_callable=io.StringIO) as err:
                        rc = hm.main(['list'])
            self.assertEqual(rc, 2)
            self.assertIn('--agent', err.getvalue())

    def test_bad_agent_target_env(self) -> None:
        with mock.patch.dict(os.environ, {'AGENT_TARGET': 'codex'}):
            with mock.patch('sys.stderr', new_callable=io.StringIO) as err:
                self.assertEqual(hm.main(['list']), 2)
            self.assertIn('unknown agent', err.getvalue())

    def test_check_args_accepts_agent_flag(self) -> None:
        with mock.patch('sys.stdout', new_callable=io.StringIO) as out:
            self.assertEqual(hm.main(['--check-args', '--agent', 'claude']), 0)
        ns = json.loads(out.getvalue())
        self.assertEqual((ns['agent'], ns['cmd']), ('claude', 'mine'))


if __name__ == '__main__':
    unittest.main()
