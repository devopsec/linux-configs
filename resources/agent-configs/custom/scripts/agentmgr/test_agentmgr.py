#!/usr/bin/env python3
"""Unit tests for agentmgr (no mutation of real junie home settings)."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

from lib.config_ops import coerce_value, get_value, set_value  # noqa: E402
from lib.paths import expand_ref_path, make_paths  # noqa: E402
from lib.pretty import markdown_toc  # noqa: E402
from lib import sadkitti as sk  # noqa: E402
from lib.steer import get_template, list_templates, scan_routing_blocks  # noqa: E402
from lib.workflow import WorkflowAudit  # noqa: E402

AGENTMGR = ROOT / 'agentmgr.py'


def run_cli(*args: str, env: dict | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(AGENTMGR), *args],
        capture_output=True,
        text=True,
        env=env or os.environ.copy(),
        timeout=60,
    )


class TestCoerceAndPaths(unittest.TestCase):
    def test_coerce(self) -> None:
        self.assertTrue(coerce_value('true'))
        self.assertFalse(coerce_value('false'))
        self.assertEqual(coerce_value('300'), 300)
        self.assertEqual(coerce_value('"x"'), 'x')
        self.assertEqual(coerce_value('[1,2]'), [1, 2])

    def test_set_get_value(self) -> None:
        data = {'a': {'b': 1}}
        self.assertEqual(get_value(data, 'a.b'), 1)
        out = set_value(data, 'a.c', 2)
        self.assertEqual(out['a']['c'], 2)
        self.assertEqual(data['a'], {'b': 1})  # deepcopy

    def test_expand_ref(self) -> None:
        home = Path.home()
        self.assertEqual(expand_ref_path('~/.junie', Path('/tmp')), (home / '.junie').resolve())
        self.assertTrue(str(expand_ref_path('/etc/hosts', Path('/tmp'))).endswith('hosts'))


class TestSadkitti(unittest.TestCase):
    def test_scan_lint_graph(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            good = root / 'ok.md'
            bad = root / 'bad.md'
            target = root / 'target.md'
            target.write_text('# Target\n', encoding='utf-8')
            good.write_text(
                '# G\n\n```sadkitti\nREQUIRE "target.md"\nREFERENCE "target.md"\n```\n',
                encoding='utf-8',
            )
            bad.write_text(
                '# B\n\n```sadkitti\nREQUIRE "missing-doc.md"\n```\n',
                encoding='utf-8',
            )
            found = sk.scan(root)
            self.assertEqual(len(found), 2)
            errors = sk.lint(root)
            self.assertEqual(len(errors), 1)
            self.assertIn('missing-doc.md', errors[0]['broken_ref'])
            graph = sk.build_graph(root)
            self.assertIn('ok.md', graph)
            text = sk.format_graph_text(graph, root)
            self.assertIn('target.md', text)
            mer = sk.build_mermaid(graph)
            self.assertIn('flowchart', mer)
            # ignore marker
            ignored = root / 'ig.md'
            ignored.write_text(
                '<!-- sadkitti-lint: ignore -->\n```sadkitti\nREQUIRE "nope.md"\n```\n',
                encoding='utf-8',
            )
            errors2 = sk.lint(root)
            # still only the one from bad.md
            self.assertEqual(len(errors2), 1)


class TestSteerAndPretty(unittest.TestCase):
    def test_templates(self) -> None:
        names = list_templates()
        self.assertIn('domain-routing', names)
        body = get_template('domain-routing')
        self.assertIn('sadkitti', body)

    def test_scan_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            f = Path(td) / 'a.md'
            f.write_text('```sadkitti\nIF x\n  REFERENCE "y"\n```\n', encoding='utf-8')
            blocks = scan_routing_blocks(Path(td))
            self.assertEqual(len(blocks), 1)
            self.assertIn('IF', blocks[0].primitives)

    def test_toc(self) -> None:
        md = '# A\n\n## B\n\n### C\n'
        toc = markdown_toc(md)
        self.assertIn('- A', toc)
        self.assertIn('- B', toc)


class TestWorkflow(unittest.TestCase):
    def test_audit_minimal(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            events = Path(td) / 'events.jsonl'
            rows = [
                {
                    'kind': 'SessionA2uxEvent',
                    'timestampMs': 1_700_000_000_000,
                    'event': {
                        'agentEvent': {
                            'kind': 'LlmResponseMetadataEvent',
                            'modelUsage': [
                                {
                                    'cost': 0.01,
                                    'inputTokens': 100,
                                    'outputTokens': 20,
                                    'cacheInputTokens': 50,
                                }
                            ],
                        }
                    },
                },
                {
                    'kind': 'SessionA2uxEvent',
                    'timestampMs': 1_700_000_000_100,
                    'event': {
                        'agentEvent': {
                            'kind': 'ToolBlockUpdatedEvent',
                            'status': 'IN_PROGRESS',
                            'text': 'REFERENCE "foo.md"',
                            'stepId': '1',
                        }
                    },
                },
            ]
            events.write_text('\n'.join(json.dumps(r) for r in rows) + '\n', encoding='utf-8')
            audit = WorkflowAudit(events_file=events)
            audit.load_events()
            audit.parse_workflow()
            self.assertEqual(audit.total_input_tokens, 100)
            self.assertEqual(audit.total_cached_tokens, 50)
            self.assertTrue(audit.guideline_references)
            summary = audit.summary_dict()
            self.assertTrue(summary['guideline_ok'])
            mer = audit.generate_mermaid()
            self.assertIn('flowchart', mer)


class TestCLISmoke(unittest.TestCase):
    def test_status_and_docs(self) -> None:
        home = str(Path.home() / '.junie')
        r = run_cli('--junie-home', home, '--no-color', 'status')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('Junie agent status', r.stdout)
        r2 = run_cli('--junie-home', home, '--no-color', 'docs', 'show', 'agents', '--format', 'toc')
        self.assertEqual(r2.returncode, 0, r2.stderr)
        self.assertTrue(len(r2.stdout) > 20)
        r3 = run_cli('--junie-home', home, '--no-color', 'skills', 'list', '--query', 'todo')
        self.assertEqual(r3.returncode, 0, r3.stderr)
        r4 = run_cli('--junie-home', home, '--no-color', 'tune', 'show')
        self.assertEqual(r4.returncode, 0, r4.stderr)
        r5 = run_cli(
            '--junie-home',
            home,
            '--no-color',
            'config',
            'set',
            'token-budget',
            '3000000',
            '--which',
            'config',
        )
        self.assertEqual(r5.returncode, 0, r5.stderr)
        self.assertIn('DRY-RUN', r5.stdout)
        r6 = run_cli('--junie-home', home, '--no-color', 'steer', 'templates')
        self.assertEqual(r6.returncode, 0, r6.stderr)
        r7 = run_cli(
            '--junie-home',
            home,
            '--no-color',
            'sadkitti',
            'lint',
            str(Path(home) / 'custom' / 'docs' / 'sadkitti'),
        )
        # sadkitti dir has ignore markers; should be OK
        self.assertEqual(r7.returncode, 0, r7.stdout + r7.stderr)

    def test_paths_json(self) -> None:
        home = str(Path.home() / '.junie')
        r = run_cli('--junie-home', home, '--json', 'paths')
        self.assertEqual(r.returncode, 0, r.stderr)
        data = json.loads(r.stdout)
        self.assertIn('home', data)


    def test_command_placeholders_and_lint(self) -> None:
        from lib.inventory import (
            extract_command_placeholders,
            list_commands,
            required_command_placeholders,
        )

        self.assertEqual(extract_command_placeholders('x $file and $file $ARGS'), ['file', 'ARGS'])
        self.assertEqual(extract_command_placeholders('no placeholders'), [])
        self.assertEqual(
            required_command_placeholders('run $prompt only', allow_prompt_argument=True),
            [],
        )
        self.assertEqual(
            required_command_placeholders('run $prompt and $file', allow_prompt_argument=True),
            ['file'],
        )
        self.assertEqual(
            required_command_placeholders('run $prompt', allow_prompt_argument=False),
            ['prompt'],
        )
        home = str(Path.home() / '.junie')
        cmds = {c.name: c for c in list_commands()}
        for name in ('histmgr', 'agentmgr', 'sectool'):
            self.assertIn(name, cmds)
            c = cmds[name]
            self.assertTrue(c.allow_prompt_argument, name)
            self.assertEqual(c.required_placeholders, [], name)
            # body uses optional $prompt only
            body = c.path.read_text(encoding='utf-8')
            self.assertIn('$prompt', body)
            self.assertNotIn('$HOME', body)
            self.assertNotIn('$ARGUMENTS', body)
        r = run_cli('--junie-home', home, '--no-color', 'commands', 'lint')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('failures: 0', r.stdout)

    def test_bare_default_status(self) -> None:
        home = str(Path.home() / '.junie')
        r = run_cli('--junie-home', home, '--no-color')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('Junie agent status', r.stdout)

    def test_check_args_no_fs_access(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            r = run_cli(
                '--junie-home', str(Path(td) / 'missing'), '--check-args', 'docs', 'show', 'agents', '--format', 'toc'
            )
            self.assertEqual(r.returncode, 0, r.stderr)
            ns = json.loads(r.stdout)
            self.assertEqual(ns['cmd'], 'docs')
            self.assertEqual(ns['format'], 'toc')
            self.assertNotIn('func', ns)
            bare = run_cli('--check-args')
            self.assertEqual(json.loads(bare.stdout)['cmd'], 'status')
            bad = run_cli('--check-args', 'docs', 'show', '--format', 'nope')
            self.assertEqual(bad.returncode, 2)

    def test_examples_extraction(self) -> None:
        from lib.inventory import extract_command_examples, extract_command_script

        body = (
            'EXECUTE\n\n```bash\npython3 ~/.junie/custom/scripts/foo/foo.py $prompt\n```\n\n'
            'Examples:\n\n```text\nlist -n 5\n\nshow abc --transcript\n```\n\n```text\nignored\n```\n'
        )
        self.assertEqual(extract_command_script(body), '~/.junie/custom/scripts/foo/foo.py')
        self.assertEqual(extract_command_examples(body), ['list -n 5', 'show abc --transcript'])
        self.assertIsNone(extract_command_script('no script here'))
        self.assertEqual(extract_command_examples('no block'), [])

    def test_lint_examples_pass_and_fail(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            home = Path(td)
            script = home / 'custom' / 'scripts' / 'fake' / 'fake.py'
            script.parent.mkdir(parents=True)
            script.write_text(
                'import sys\n'
                "sys.exit(0 if sys.argv[1:2] == ['--check-args'] and 'bad' not in sys.argv else 2)\n",
                encoding='utf-8',
            )
            cmds = home / 'commands'
            cmds.mkdir()
            good_body = (
                '---\ndescription: "good"\nallowPromptArgument: true\n---\n'
                '```bash\npython3 ~/.junie/custom/scripts/fake/fake.py $prompt\n```\n'
                '```text\nlist -n 5\nshow x\n```\n'
            )
            (cmds / 'good.md').write_text(good_body, encoding='utf-8')
            r = run_cli('--junie-home', str(home), '--no-color', 'commands', 'lint', '--examples')
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertIn('examples: 2/2 parse OK', r.stdout)

            (cmds / 'bad.md').write_text(good_body.replace('show x', 'show bad\nshow "unterminated'), encoding='utf-8')
            (cmds / 'noex.md').write_text(
                '---\ndescription: "n"\nallowPromptArgument: true\n---\n'
                '```bash\npython3 ~/.junie/custom/scripts/fake/fake.py $prompt\n```\n',
                encoding='utf-8',
            )
            r2 = run_cli('--junie-home', str(home), '--no-color', '--json', 'commands', 'lint', '--examples')
            self.assertEqual(r2.returncode, 1, r2.stdout + r2.stderr)
            by_name = {e['name']: e for e in json.loads(r2.stdout)}
            self.assertTrue(by_name['good']['ok'])
            self.assertFalse(by_name['bad']['ok'])
            bad_problems = ' '.join(by_name['bad']['problems'])
            self.assertIn('example #2 `show bad` fails: exit 2', bad_problems)
            self.assertIn('unparseable shell words', bad_problems)
            self.assertTrue(by_name['noex']['ok'], 'missing example block is a warning, not a failure')
            self.assertIn('no ```text example block', ' '.join(by_name['noex']['problems']))
            # without --examples the broken example is not inspected
            r3 = run_cli('--junie-home', str(home), '--no-color', 'commands', 'lint')
            self.assertEqual(r3.returncode, 0, r3.stdout + r3.stderr)
            r4 = run_cli('--junie-home', str(home), '--no-color', 'commands', 'show', 'good')
            self.assertEqual(r4.returncode, 0, r4.stderr)
            self.assertIn('examples: 2', r4.stdout)


def _make_home(td: str) -> Path:
    home = Path(td)
    (home / 'config.json').write_text('{}', encoding='utf-8')
    (home / 'settings.json').write_text('{}', encoding='utf-8')
    sk_dir = home / 'skills' / 'dev-bash-script-review'
    sk_dir.mkdir(parents=True)
    (sk_dir / 'SKILL.md').write_text('---\nname: dev-bash-script-review\ndescription: x\n---\n# X\n', encoding='utf-8')
    val = home / 'skills' / 'dev-agents-skill-create' / 'scripts'
    val.mkdir(parents=True)
    (val / 'validate.py').write_text('print("VERDICT OK")\n', encoding='utf-8')
    (home / 'skills' / 'dev-agents-skill-create' / 'SKILL.md').write_text('# v\n', encoding='utf-8')
    (home / 'commands').mkdir()
    (home / 'commands' / 'agentmgr.md').write_text('---\ndescription: x\n---\nbody\n', encoding='utf-8')
    return home


class TestGlobalFlagPlacement(unittest.TestCase):
    def _ns(self, *args: str) -> dict:
        r = run_cli('--check-args', *args)
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def test_defaults_unchanged(self) -> None:
        ns = self._ns('status')
        self.assertEqual(
            {k: ns[k] for k in ('json', 'no_color', 'color', 'junie_home')},
            {'json': False, 'no_color': False, 'color': False, 'junie_home': None},
        )

    def test_before_and_after(self) -> None:
        self.assertTrue(self._ns('--json', 'status')['json'])
        self.assertTrue(self._ns('status', '--json')['json'])
        self.assertTrue(self._ns('status', '--no-color')['no_color'])
        self.assertTrue(self._ns('status', '--color')['color'])
        self.assertEqual(self._ns('status', '--junie-home', '/tmp/x')['junie_home'], '/tmp/x')
        self.assertEqual(self._ns('--junie-home', '/tmp/x', 'status')['junie_home'], '/tmp/x')
        self.assertEqual(self._ns('--json')['cmd'], 'status')

    def test_status_json_trailing(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            home = _make_home(td)
            r = run_cli('status', '--json', '--junie-home', str(home))
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(json.loads(r.stdout)['home'], str(home))

    def test_help_examples(self) -> None:
        for name in ('status', 'paths', 'inventory', 'docs', 'skills', 'commands', 'config',
                     'tune', 'steer', 'workflow', 'sadkitti', 'test', 'mcp', 'models'):
            r = run_cli(name, '-h')
            self.assertEqual(r.returncode, 0, name)
            self.assertIn('Examples', r.stdout, name)
        self.assertIn('.agentmgr-backups/', run_cli('tune', '-h').stdout)


class TestSettersBackupJson(unittest.TestCase):
    def test_tune_set_backup(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            home = _make_home(td)
            r = run_cli('tune', 'set', 'token-budget', '1', '--write', '--no-backup', '--junie-home', str(home))
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertFalse((home / '.agentmgr-backups').exists())
            self.assertEqual(json.loads((home / 'config.json').read_text())['token-budget'], 1)
            r = run_cli('tune', 'set', 'token-budget', '2', '--write', '--junie-home', str(home))
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertTrue((home / '.agentmgr-backups').is_dir())

    def test_tune_effort_no_backup(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            home = _make_home(td)
            r = run_cli('tune', 'effort', '--model', 'm1', '--effort', 'low', '--write', '--no-backup',
                        '--junie-home', str(home))
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertFalse((home / '.agentmgr-backups').exists())
            self.assertIn('m1', json.loads((home / 'settings.json').read_text())['effortPerModel'])
            r = run_cli('tune', 'effort', '--model', 'm1', '--effort', 'high', '--write', '--junie-home', str(home))
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertTrue((home / '.agentmgr-backups').is_dir())

    def test_tune_set_json(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            home = _make_home(td)
            r = run_cli('tune', 'set', 'token-budget', '5', '--json', '--junie-home', str(home))
            self.assertEqual(r.returncode, 0, r.stderr)
            data = json.loads(r.stdout)
            self.assertEqual((data['key'], data['old'], data['new'], data['dry_run']), ('token-budget', None, 5, True))


class TestNotFoundHints(unittest.TestCase):
    def _check(self, home: Path, args: tuple[str, ...], expect: str) -> None:
        r = run_cli(*args, '--junie-home', str(home))
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertEqual(r.stdout, '')
        self.assertIn(expect, r.stderr)

    def test_hints(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            home = _make_home(td)
            near = 'did you mean'
            self._check(home, ('skills', 'show', 'dev-bash-script-reviw'), near)
            self._check(home, ('skills', 'validate', 'dev-bash-script-reviw'), near)
            self._check(home, ('commands', 'show', 'agentmg'), near)
            self._check(home, ('docs', 'show', 'agnts'), near)
            self._check(home, ('skills', 'show', 'zzqqxx'), 'agentmgr skills list')
            self._check(home, ('skills', 'validate', 'zzqqxx'), 'agentmgr skills list')
            self._check(home, ('commands', 'show', 'zzqqxx'), 'agentmgr commands list')
            self._check(home, ('docs', 'show', 'zzqqxx'), 'agentmgr docs list')


class TestSubcommandUsability(unittest.TestCase):
    def _home(self, td: str) -> str:
        (Path(td) / 'config.json').write_text('{"token-budget": 5}', encoding='utf-8')
        (Path(td) / 'settings.json').write_text('{"model": "a"}', encoding='utf-8')
        return td

    def test_config_set_infers_target(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            home = self._home(td)
            r = run_cli('config', 'set', 'model', 'b', '--json', '--junie-home', home)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(json.loads(r.stdout)['target'], 'settings')
            r = run_cli('config', 'set', 'token-budget', '7', '--json', '--junie-home', home)
            self.assertEqual(json.loads(r.stdout)['target'], 'config')

    def test_config_get_hint(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            r = run_cli('config', 'get', 'token-budgte', '--junie-home', self._home(td))
            self.assertEqual(r.returncode, 2)
            self.assertEqual(r.stdout, '')
            self.assertIn('did you mean: token-budget', r.stderr)

    def test_tune_effort_positional(self) -> None:
        r = run_cli('--check-args', 'tune', 'effort', 'M', 'low')
        self.assertEqual(r.returncode, 0, r.stderr)
        with tempfile.TemporaryDirectory() as td:
            r = run_cli('tune', 'effort', '--junie-home', self._home(td))
            self.assertEqual(r.returncode, 2)
            self.assertIn('MODEL EFFORT', r.stderr)

    def test_steer_show_hint(self) -> None:
        r = run_cli('steer', 'show', 'domain-routng')
        self.assertEqual(r.returncode, 2)
        self.assertEqual(r.stdout, '')
        self.assertIn('did you mean: domain-routing', r.stderr)


if __name__ == '__main__':
    unittest.main()
