#!/usr/bin/env python3
"""Run skill-trigger cases with Junie CLI in an isolated headless session."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


class EvaluationError(ValueError):
    """Raised when an evaluation input or Junie run is invalid."""


@dataclass(frozen=True)
class EvalCase:
    case_id: str
    prompt: str
    expected: str | None
    kind: str


NAME_PATTERN = re.compile(r'(?m)^name:\s*["\']?([A-Za-z0-9]+(?:-[A-Za-z0-9]+)+)["\']?\s*$')
TOOL_PATTERN = re.compile(r'\bagent_skill_read_doc\b')
NAME_FIELD_PATTERN = re.compile(r'["\']?name["\']?\s*[:=]\s*["\']?([A-Za-z0-9]+(?:-[A-Za-z0-9]+)+)')


def load_skill_names(skills_root: Path) -> set[str]:
    """Read exact skill names from direct child SKILL.md frontmatter."""
    if skills_root.is_symlink() or not skills_root.is_dir():
        raise EvaluationError(f"skills root is not a directory: {skills_root}")

    names: set[str] = set()
    for skill_dir in sorted(skills_root.iterdir()):
        if skill_dir.is_symlink() or not skill_dir.is_dir():
            continue
        skill_file = skill_dir / 'SKILL.md'
        if skill_file.is_symlink() or not skill_file.is_file():
            continue
        content = skill_file.read_text(encoding='utf-8')
        frontmatter = re.match(r'\A---\s*\n(.*?)\n---\s*(?:\n|$)', content, re.DOTALL)
        if frontmatter is None:
            raise EvaluationError(f"missing YAML frontmatter: {skill_file}")
        match = NAME_PATTERN.search(frontmatter.group(1))
        if match is None:
            raise EvaluationError(f"missing skill name in frontmatter: {skill_file}")
        name = match.group(1)
        if name != skill_dir.name:
            raise EvaluationError(f"folder/name mismatch in {skill_file}: {name}")
        if name in names:
            raise EvaluationError(f"duplicate skill name in catalog: {name}")
        names.add(name)

    if not names:
        raise EvaluationError(f"no readable skill directories found: {skills_root}")
    return names


def load_cases(dataset: Path, skill_names: set[str]) -> list[EvalCase]:
    """Load and validate a JSONL trigger dataset."""
    if not dataset.is_file():
        raise EvaluationError(f"dataset is not a file: {dataset}")

    cases: list[EvalCase] = []
    seen_ids: set[str] = set()
    for line_number, line in enumerate(dataset.read_text(encoding='utf-8').splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as err:
            raise EvaluationError(f"invalid JSON on line {line_number}: {err.msg}") from err
        if not isinstance(row, dict):
            raise EvaluationError(f"line {line_number} must be a JSON object")

        case_id = row.get('id')
        prompt = row.get('prompt')
        expected = row.get('expect')
        kind = row.get('kind')
        if not isinstance(case_id, str) or not case_id.strip():
            raise EvaluationError(f"line {line_number} needs a non-empty string id")
        if case_id in seen_ids:
            raise EvaluationError(f"duplicate case id on line {line_number}: {case_id}")
        if not isinstance(prompt, str) or not prompt.strip():
            raise EvaluationError(f"line {line_number} needs a non-empty string prompt")
        if expected is not None and (not isinstance(expected, str) or expected not in skill_names):
            raise EvaluationError(f"line {line_number} expects a skill missing from the catalog")
        if not isinstance(kind, str) or kind not in {'positive', 'near-miss', 'negative'}:
            raise EvaluationError(f"line {line_number} has an unsupported kind")
        if kind == 'positive' and expected is None:
            raise EvaluationError(f"positive case on line {line_number} needs an expected skill")
        if kind == 'negative' and expected is not None:
            raise EvaluationError(f"negative case on line {line_number} must expect null")

        seen_ids.add(case_id)
        cases.append(EvalCase(case_id, prompt, expected, kind))

    if not cases:
        raise EvaluationError("dataset contains no cases")
    return cases


def extract_triggered_skills(transcript: str, skill_names: set[str]) -> set[str]:
    """Find known skill names passed to a recorded skill-read tool call."""
    triggered: set[str] = set()
    events = list(TOOL_PATTERN.finditer(transcript))
    for index, event in enumerate(events):
        end = min(len(transcript), event.end() + 1536)
        if index + 1 < len(events):
            end = min(end, events[index + 1].start())
        block = transcript[event.end():end]
        for field in NAME_FIELD_PATTERN.finditer(block):
            if field.group(1) in skill_names:
                triggered.add(field.group(1))
        for name in skill_names:
            if re.search(rf'[\\/]skills[\\/]{re.escape(name)}[\\/]', block):
                triggered.add(name)
    return triggered


def ignore_symlinks(directory: str, names: list[str]) -> set[str]:
    """Prevent a copied evaluation catalog from following links outside its root."""
    return {name for name in names if (Path(directory) / name).is_symlink()}


def build_command(
    junie_cli: str,
    api_key: str,
    project_dir: Path,
    skills_root: Path,
    session_id: str,
    cache_dir: Path,
) -> list[str]:
    """Build documented Junie headless arguments; prompt is passed on stdin."""
    return [
        junie_cli,
        '--auth',
        api_key,
        '--input-format',
        'text',
        '--output-format',
        'json',
        '--project',
        str(project_dir),
        '--session-id',
        session_id,
        '--skill-location',
        str(skills_root),
        '--skill-default-locations',
        'false',
        '--config-default-locations',
        'false',
        '--mcp-default-locations',
        'false',
        '--command-default-location',
        'false',
        '--agent-default-location',
        'false',
        '--cache-dir',
        str(cache_dir),
        '--max-steps',
        '25',
        '--skip-update-check',
    ]


def run_case(
    case: EvalCase,
    junie_cli: str,
    api_key: str,
    skills_root: Path,
    skill_names: set[str],
    timeout_seconds: int,
) -> set[str]:
    """Run one prompt against a temporary catalog without modifying the source tree."""
    with tempfile.TemporaryDirectory(prefix='junie-skill-eval-') as temp_root:
        isolated_root = Path(temp_root)
        junie_home = isolated_root / 'junie-home'
        project_dir = isolated_root / 'project'
        cache_dir = isolated_root / 'cache'
        isolated_skills = isolated_root / 'skills'
        junie_home.mkdir()
        project_dir.mkdir()
        cache_dir.mkdir()
        shutil.copytree(skills_root, isolated_skills, ignore=ignore_symlinks)

        session_id = uuid.uuid4().hex
        command = build_command(junie_cli, api_key, project_dir, isolated_skills, session_id, cache_dir)
        inherited_names = {'HOME', 'LANG', 'LC_ALL', 'LOGNAME', 'PATH', 'SYSTEMROOT', 'TEMP', 'TMP', 'TMPDIR', 'USER'}
        environment = {key: value for key, value in os.environ.items() if key in inherited_names}
        environment['JUNIE_HOME'] = str(junie_home)
        environment['JUNIE_SKIP_UPDATE_CHECK'] = '1'

        try:
            subprocess.run(
                command,
                input=case.prompt,
                cwd=project_dir,
                env=environment,
                capture_output=True,
                check=True,
                text=True,
                timeout=timeout_seconds,
            )
        except subprocess.TimeoutExpired as err:
            raise EvaluationError(f"Junie timed out for case {case.case_id}") from err
        except subprocess.CalledProcessError as err:
            raise EvaluationError(f"Junie returned exit status {err.returncode} for case {case.case_id}") from err
        except OSError as err:
            raise EvaluationError(f"could not start Junie for case {case.case_id}: {err.strerror}") from err

        transcripts = list(junie_home.rglob('transcript.md'))
        if len(transcripts) != 1:
            raise EvaluationError(
                f"expected one isolated transcript for case {case.case_id}; found {len(transcripts)}"
            )
        return extract_triggered_skills(transcripts[0].read_text(encoding='utf-8'), skill_names)


def build_report(
    cases: list[EvalCase],
    observations: dict[str, list[set[str]]],
    skill_names: set[str],
) -> dict[str, object]:
    """Summarize exact routing, majority routing, precision, recall, and confusions."""
    if not cases:
        raise EvaluationError("no cases to score")
    run_count = len(observations.get(cases[0].case_id, []))
    if run_count == 0 or any(len(observations.get(case.case_id, [])) != run_count for case in cases):
        raise EvaluationError("observations must contain the same non-zero run count for every case")
    majority_threshold = (run_count // 2) + 1
    total_runs = 0
    exact_passes = 0
    case_reports: list[dict[str, object]] = []
    counts: dict[str, Counter[str]] = {
        name: Counter({'tp': 0, 'fp': 0, 'fn': 0}) for name in skill_names
    }

    for case in cases:
        runs = observations[case.case_id]
        if not runs:
            raise EvaluationError(f"no observations for case {case.case_id}")
        expected_set = {case.expected} if case.expected is not None else set()
        majority_observed = {
            name for name in skill_names if sum(name in observed for observed in runs) >= majority_threshold
        }
        passes = sum(observed == expected_set for observed in runs)
        total_runs += len(runs)
        exact_passes += passes

        for observed in runs:
            for name in skill_names:
                expected = case.expected == name
                actual = name in observed
                if expected and actual:
                    counts[name]['tp'] += 1
                elif not expected and actual:
                    counts[name]['fp'] += 1
                elif expected and not actual:
                    counts[name]['fn'] += 1

        case_reports.append(
            {
                'id': case.case_id,
                'kind': case.kind,
                'expected': case.expected,
                'observed_per_run': [sorted(observed) for observed in runs],
                'majority_observed': sorted(majority_observed),
                'majority_pass': majority_observed == expected_set,
                'exact_pass_rate': passes / len(runs),
            }
        )

    per_skill: dict[str, dict[str, float | int]] = {}
    for name, values in sorted(counts.items()):
        predictions = values['tp'] + values['fp']
        expected = values['tp'] + values['fn']
        per_skill[name] = {
            'precision': values['tp'] / predictions if predictions else 0.0,
            'recall': values['tp'] / expected if expected else 0.0,
            'true_positive': values['tp'],
            'false_positive': values['fp'],
            'false_negative': values['fn'],
        }

    return {
        'summary': {
            'case_count': len(cases),
            'run_count': total_runs,
            'exact_accuracy': exact_passes / total_runs if total_runs else 0.0,
            'per_skill': per_skill,
        },
        'cases': case_reports,
    }


def positive_int(value: str) -> int:
    """Parse a positive integer CLI argument."""
    try:
        number = int(value)
    except ValueError as err:
        raise argparse.ArgumentTypeError('must be an integer') from err
    if number < 1:
        raise argparse.ArgumentTypeError('must be greater than zero')
    return number


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description='Run Junie skill-trigger evaluations in headless mode.')
    parser.add_argument('dataset', type=Path, help='JSONL file with id, prompt, expect, and kind fields')
    parser.add_argument('--skills-root', required=True, type=Path, help='directory containing skill folders')
    parser.add_argument('--junie', default='junie', help='Junie CLI executable (default: junie)')
    parser.add_argument('--runs', default=3, type=positive_int, help='runs per prompt (default: 3)')
    parser.add_argument('--timeout', default=300, type=positive_int, help='seconds per Junie run (default: 300)')
    parser.add_argument('--output', type=Path, help='write summary JSON to a new file instead of stdout')
    parser.add_argument('--dry-run', action='store_true', help='validate inputs and print a non-sensitive run plan')
    parser.add_argument('--yes', action='store_true', help='confirm provider-cost headless runs')
    parser.add_argument(
        '--isolated-runner',
        action='store_true',
        help='confirm this process runs in a disposable, single-user environment without real project data',
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = make_parser()
    args = parser.parse_args(argv)
    try:
        skill_names = load_skill_names(args.skills_root)
        cases = load_cases(args.dataset, skill_names)
        if args.dry_run:
            print(
                json.dumps(
                    {
                        'dry_run': True,
                        'junie_cli': args.junie,
                        'headless': True,
                        'skill_count': len(skill_names),
                        'case_count': len(cases),
                        'runs_per_case': args.runs,
                        'authentication_required': True,
                        'confirmation_required': ['--yes', '--isolated-runner'],
                    },
                    indent=2,
                )
            )
            return 0

        if not args.yes or not args.isolated_runner:
            parser.error('live runs require both --yes and --isolated-runner')
        api_key = os.environ.get('JUNIE_API_KEY')
        if not api_key:
            parser.error('set JUNIE_API_KEY in the environment for this isolated run')
        if args.output is not None and args.output.exists():
            raise EvaluationError(f'output already exists; choose a new path: {args.output}')

        observations: dict[str, list[set[str]]] = {}
        for case in cases:
            observations[case.case_id] = [
                run_case(case, args.junie, api_key, args.skills_root.resolve(), skill_names, args.timeout)
                for _ in range(args.runs)
            ]

        report = build_report(cases, observations, skill_names)
        serialized = json.dumps(report, indent=2, sort_keys=True) + '\n'
        if args.output is None:
            print(serialized, end='')
        else:
            if not args.output.parent.is_dir():
                raise EvaluationError(f'output directory does not exist: {args.output.parent}')
            args.output.write_text(serialized, encoding='utf-8')
            print(f"Wrote summary to {args.output}")
        return 0
    except (EvaluationError, OSError) as err:
        parser.exit(2, f"error: {err}\n")


if __name__ == '__main__':
    sys.exit(main())