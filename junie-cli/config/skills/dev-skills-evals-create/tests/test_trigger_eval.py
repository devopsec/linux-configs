import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))

import trigger_eval  # noqa: E402
from trigger_eval import (
    EvalCase,
    EvaluationError,
    build_report,
    extract_triggered_skills,
    load_cases,
    load_skill_names,
    run_case,
)  # noqa: E402


class TriggerEvalTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(temporary_directory.cleanup)
        self.root = Path(temporary_directory.name)

    def write_skill(self, catalog: Path, name: str) -> Path:
        skill_dir = catalog / name
        skill_dir.mkdir(parents=True)
        skill_file = skill_dir / 'SKILL.md'
        skill_file.write_text(f"---\nname: {name}\n---\n", encoding='utf-8')
        return skill_file

    def test_load_skill_names_requires_folder_name_match(self) -> None:
        self.write_skill(self.root, 'dev-example-skill-create')

        self.assertEqual(load_skill_names(self.root), {'dev-example-skill-create'})

    def test_load_skill_names_rejects_mismatched_frontmatter(self) -> None:
        skill_file = self.write_skill(self.root, 'dev-example-skill-create')
        skill_file.write_text('---\nname: dev-other-skill-create\n---\n', encoding='utf-8')

        with self.assertRaisesRegex(EvaluationError, 'folder/name mismatch'):
            load_skill_names(self.root)

    def test_load_cases_accepts_positive_near_miss_and_negative_rows(self) -> None:
        dataset = self.root / 'triggers.jsonl'
        rows = [
            {'id': 'p1', 'prompt': 'run an eval', 'expect': 'dev-agent-evals-create', 'kind': 'positive'},
            {'id': 'n1', 'prompt': 'create a new skill', 'expect': 'dev-agent-evals-create', 'kind': 'near-miss'},
            {'id': 'x1', 'prompt': 'rename a variable', 'expect': None, 'kind': 'negative'},
        ]
        dataset.write_text('\n'.join(json.dumps(row) for row in rows), encoding='utf-8')

        cases = load_cases(dataset, {'dev-agent-evals-create'})

        self.assertEqual([case.case_id for case in cases], ['p1', 'n1', 'x1'])
        self.assertIsNone(cases[2].expected)

    def test_load_cases_rejects_missing_expected_skill(self) -> None:
        dataset = self.root / 'triggers.jsonl'
        dataset.write_text(
            json.dumps({'id': 'p1', 'prompt': 'run an eval', 'expect': 'dev-missing-skill-create', 'kind': 'positive'}),
            encoding='utf-8',
        )

        with self.assertRaisesRegex(EvaluationError, 'missing from the catalog'):
            load_cases(dataset, {'dev-agent-evals-create'})

    def test_dry_run_validates_without_api_key(self) -> None:
        skill_name = 'dev-example-skill-create'
        catalog = self.root / 'catalog'
        self.write_skill(catalog, skill_name)
        dataset = self.root / 'triggers.jsonl'
        dataset.write_text(
            json.dumps({'id': 'p1', 'prompt': 'safe prompt', 'expect': skill_name, 'kind': 'positive'}),
            encoding='utf-8',
        )
        output = StringIO()

        with redirect_stdout(output):
            exit_code = trigger_eval.main([str(dataset), '--skills-root', str(catalog), '--dry-run'])

        self.assertEqual(exit_code, 0)
        self.assertTrue(json.loads(output.getvalue())['dry_run'])

    def test_extract_triggered_skills_requires_a_skill_read_event(self) -> None:
        names = {'dev-agent-evals-create', 'dev-skills-evals-create'}
        transcript = (
            'agent_skill_read_doc: {"name": "dev-skills-evals-create", "path": null}\n'
            'Related skill: dev-agent-evals-create'
        )

        self.assertEqual(extract_triggered_skills(transcript, names), {'dev-skills-evals-create'})

    def test_report_scores_correct_and_unexpected_skill_loads(self) -> None:
        cases = [
            EvalCase('p1', 'run an eval', 'dev-agent-evals-create', 'positive'),
            EvalCase('n1', 'rename a variable', None, 'negative'),
        ]
        observed = {
            'p1': [{'dev-agent-evals-create'}, {'dev-agent-evals-create'}],
            'n1': [{'dev-agent-evals-create'}, set()],
        }

        report = build_report(cases, observed, {'dev-agent-evals-create'})

        self.assertEqual(report['summary']['exact_accuracy'], 0.75)
        metrics = report['summary']['per_skill']['dev-agent-evals-create']
        self.assertAlmostEqual(metrics['precision'], 2 / 3)
        self.assertEqual(metrics['recall'], 1.0)
        self.assertEqual(metrics['false_positive'], 1)

    def test_run_case_uses_a_copied_catalog_and_isolated_home(self) -> None:
        skill_name = 'dev-example-skill-create'
        catalog = self.root / 'catalog'
        skill_file = self.write_skill(catalog, skill_name)
        case = EvalCase('p1', 'safe test prompt', skill_name, 'positive')

        def fake_run(
            command: list[str],
            *,
            input: str,
            cwd: Path,
            env: dict[str, str],
            **kwargs: object,
        ) -> None:
            self.assertEqual(input, 'safe test prompt')
            self.assertNotIn(input, command)
            self.assertNotEqual(cwd, catalog)
            self.assertNotEqual(command[command.index('--skill-location') + 1], str(catalog.resolve()))
            session_id = command[command.index('--session-id') + 1]
            transcript = Path(env['JUNIE_HOME']) / 'sessions' / session_id / 'transcript.md'
            transcript.parent.mkdir(parents=True)
            transcript.write_text(f"agent_skill_read_doc: {{\"name\": \"{skill_name}\"}}", encoding='utf-8')

        with patch.object(trigger_eval.subprocess, 'run', fake_run):
            observed = run_case(case, 'junie', 'mock-api-key', catalog, {skill_name}, 10)

        self.assertEqual(observed, {skill_name})
        self.assertEqual(skill_file.read_text(encoding='utf-8'), f"---\nname: {skill_name}\n---\n")


if __name__ == '__main__':
    unittest.main()