#!/usr/bin/env python3
"""
agentmgr — advanced Junie agent management CLI.

Inventory skills/commands/docs, pretty-print agent documentation, tune
config/settings, scaffold decision-routing (SAD KITTI), validate skills,
and test workflows (events audit + sadkitti scan/lint/graph).
"""

from __future__ import annotations

import argparse
import difflib
import json
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Sequence

# Allow running as script: ensure package root on path
_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from lib.config_ops import apply_set, coerce_value, get_value, show_config  # noqa: E402
from lib.docs_render import (  # noqa: E402
    render_commands_cards,
    render_doc,
    render_docs_tree,
    render_index,
    render_skills_cards,
    resolve_doc_target,
)
from lib.inventory import (  # noqa: E402
    list_commands,
    list_models,
    list_skills,
    load_mcp,
    status_snapshot,
)
from lib.paths import find_project_agents_roots, make_paths  # noqa: E402
from lib.pretty import Style, bullet_list, header, hr, kv, table  # noqa: E402
from lib import sadkitti as sk  # noqa: E402
from lib.steer import (  # noqa: E402
    default_scan_roots,
    get_template,
    list_templates,
    render_routing_report,
    scaffold_steering_doc,
    scan_routing_blocks,
)
from lib.tune import recommend_tuning, render_tuning, set_effort, tuning_snapshot  # noqa: E402
from lib.workflow import run_audit  # noqa: E402


def _style(args: argparse.Namespace) -> Style:
    if getattr(args, 'no_color', False):
        return Style(enabled=False)
    if getattr(args, 'color', False):
        return Style(enabled=True)
    return Style()


def _paths(args: argparse.Namespace):
    return make_paths(getattr(args, 'junie_home', None))


def _print(text: str) -> int:
    sys.stdout.write(text)
    if text and not text.endswith('\n'):
        sys.stdout.write('\n')
    return 0


def _die(msg: str, code: int = 2) -> int:
    print(msg, file=sys.stderr)
    return code


def _not_found(kind: str, name: str, candidates: Sequence[str], list_cmd: str, detail: str | None = None) -> int:
    """Report a missing item on stderr with close-match suggestions; exit 2."""
    print(f'{kind} not found: {detail or name}', file=sys.stderr)
    close = difflib.get_close_matches(name, list(candidates), n=3, cutoff=0.5)
    if close:
        print(f'hint: did you mean: {", ".join(close)}?', file=sys.stderr)
    else:
        print(f'hint: run `agentmgr {list_cmd}` to see available names', file=sys.stderr)
    return 2


_SETTINGS_KEYS = (
    'model',
    'modelForLaunch',
    'braveMode',
    'subagentsMode',
    'ecoMode',
    'eventDensityMode',
    'diffViewMode',
    'provider',
)


def _infer_target(key: str) -> str:
    """settings.json for known settings keys, config.json otherwise."""
    return 'settings' if key.split('.', 1)[0] in _SETTINGS_KEYS else 'config'


def _flat_keys(blob, prefix: str = '') -> list[str]:
    keys: list[str] = []
    if isinstance(blob, dict):
        for k, v in blob.items():
            full = f'{prefix}{k}'
            keys.append(full)
            keys.extend(_flat_keys(v, full + '.'))
    return keys


def _skill_names(p) -> list[str]:
    names: set[str] = set()
    for sk_ in list_skills(p):
        names.add(sk_.name)
        names.add(sk_.path.name)
    return sorted(names)


# ── status / paths / inventory ───────────────────────────────────────────


def cmd_status(args: argparse.Namespace) -> int:
    p = _paths(args)
    s = _style(args)
    snap = status_snapshot(p)
    if args.json:
        return _print(json.dumps(snap, indent=2, default=str))
    lines = [
        header('Junie agent status', s),
        kv('home', snap['home'], s),
        kv('skills', f"{snap['skills']} ({snap['skills_with_skill_md']} with SKILL.md)", s),
        kv('missing junie.md', snap['skills_missing_junie_agent'], s),
        kv('commands', snap['commands'], s),
        kv('models', snap['models'], s),
        kv('mcp servers', f"{snap['mcp_servers']} ({snap['mcp_enabled']} enabled-ish)", s),
        kv('sessions', snap['sessions'], s),
        hr(),
        kv('provider', snap.get('provider'), s),
        kv('model', snap.get('model'), s),
        kv('modelForLaunch', snap.get('modelForLaunch'), s),
        kv('braveMode', snap.get('braveMode'), s),
        kv('token-budget', snap.get('token_budget'), s),
        kv('time-limit', snap.get('time_limit'), s),
        kv('brave (config)', snap.get('brave_flag'), s),
    ]
    proj = find_project_agents_roots()
    lines.append(hr())
    lines.append(s.bold('Project AGENTS (cwd↑)'))
    if proj:
        for pr in proj[:8]:
            lines.append(f'  - {pr}')
    else:
        lines.append('  (none)')
    return _print('\n'.join(str(x) for x in lines))


def cmd_paths(args: argparse.Namespace) -> int:
    p = _paths(args)
    s = _style(args)
    mapping = {
        'home': p.home,
        'AGENTS.md': p.agents_md,
        'config.json': p.config,
        'settings.json': p.settings,
        'skills/': p.skills,
        'commands/': p.commands,
        'custom/bin/': p.bin,
        'custom/docs/': p.custom_docs,
        'sadkitti/': p.sadkitti,
        'scripts/': p.scripts,
        'sessions/': p.sessions,
        'mcp.json': p.mcp,
        'models/': p.models,
        'validate.py': p.validate_py,
        'skills-catalog': p.skills_catalog,
        'commands-catalog': p.commands_catalog,
    }
    if args.json:
        return _print(json.dumps({k: str(v) for k, v in mapping.items()}, indent=2))
    lines = [header('Resolved Junie paths', s)]
    for k, v in mapping.items():
        mark = s.green('✓') if Path(v).exists() else s.red('✗')
        lines.append(f'{mark} {k:<18} {v}')
    return _print('\n'.join(lines))


def cmd_inventory(args: argparse.Namespace) -> int:
    p = _paths(args)
    s = _style(args)
    parts = []
    if args.what in ('all', 'docs'):
        parts.append(render_docs_tree(p, s))
    if args.what in ('all', 'commands'):
        parts.append(render_commands_cards(paths=p, style=s))
    if args.what in ('all', 'skills'):
        parts.append(render_skills_cards(paths=p, style=s, limit=args.limit or 0))
    if args.what in ('all', 'models'):
        models = list_models(p)
        rows = []
        for m in models:
            mid = m.data.get('id', m.file_stem)
            api = m.data.get('apiType', '-')
            rows.append((m.file_stem, str(mid), str(api)))
        parts.append(header(f'Models ({len(models)})', s))
        parts.append(table(rows, headers=('file', 'id', 'apiType')))
    if args.what in ('all', 'mcp'):
        mcp = load_mcp(p)
        servers = mcp.get('mcpServers') or {}
        rows = []
        for name, cfg in sorted(servers.items()):
            if not isinstance(cfg, dict):
                rows.append((name, '?', '?'))
                continue
            en = cfg.get('enabled', True)
            cmd = cfg.get('command', '')
            rows.append((name, str(en), str(cmd)[:50]))
        parts.append(header(f'MCP servers ({len(servers)})', s))
        parts.append(table(rows, headers=('name', 'enabled', 'command')))
    return _print('\n\n'.join(parts))


# ── docs ─────────────────────────────────────────────────────────────────


def cmd_docs(args: argparse.Namespace) -> int:
    p = _paths(args)
    s = _style(args)
    if args.action == 'tree' or (args.action == 'show' and not args.target):
        if args.format == 'cards':
            return _print(render_index(p, s))
        return _print(render_docs_tree(p, s))
    if args.action == 'index':
        return _print(
            render_index(
                p,
                s,
                include_skills=not args.no_skills,
                include_commands=not args.no_commands,
            )
        )
    if args.action == 'list':
        from lib.inventory import list_guideline_docs

        docs = list_guideline_docs(p)
        if args.json:
            return _print(json.dumps([str(d) for d in docs], indent=2))
        lines = [header(f'Docs ({len(docs)})', s)]
        for d in docs:
            try:
                rel = d.relative_to(p.home)
            except ValueError:
                rel = d
            lines.append(f'  {rel}')
        return _print('\n'.join(str(x) for x in lines))

    # show
    target = args.target
    if not target:
        return _die('docs show requires a target (agents, guidelines, skill:NAME, path, …)')
    path = resolve_doc_target(target, p)
    if path is None:
        from lib.inventory import list_guideline_docs

        cands = ['agents', 'guidelines'] + sorted({d.stem for d in list_guideline_docs(p)})
        return _not_found('doc target', target, cands, 'docs list', detail=repr(target))
    fmt = args.format if args.format != 'cards' else 'pretty'
    return _print(render_doc(path, fmt=fmt, max_chars=args.max_chars, style=s))  # type: ignore[arg-type]


# ── skills / commands ────────────────────────────────────────────────────


def cmd_skills(args: argparse.Namespace) -> int:
    p = _paths(args)
    s = _style(args)
    if args.action == 'list':
        skills = list_skills(p, query=args.query)
        if args.json:
            data = [
                {
                    'name': sk.name,
                    'path': str(sk.path),
                    'description': sk.description,
                    'has_skill_md': sk.has_skill_md,
                    'has_agents_junie': sk.has_agents_junie,
                    'has_agents_claude': sk.has_agents_claude,
                    'has_references': sk.has_references,
                    'has_scripts': sk.has_scripts,
                }
                for sk in skills
            ]
            return _print(json.dumps(data, indent=2))
        return _print(render_skills_cards(skills, paths=p, style=s, limit=args.limit or 0))
    if args.action == 'show':
        if not args.name:
            return _die('skills show requires a skill name')
        path = p.skills / args.name / 'SKILL.md'
        if not path.is_file():
            # try match by frontmatter name
            matches = [sk for sk in list_skills(p) if sk.name == args.name or sk.path.name == args.name]
            if not matches:
                return _not_found('skill', args.name, _skill_names(p), 'skills list')
            path = matches[0].path / 'SKILL.md'
        return _print(render_doc(path, fmt=args.format, max_chars=args.max_chars, style=s))  # type: ignore[arg-type]
    if args.action == 'validate':
        return _validate_skills(args, p, s)
    return _die(f'unknown skills action: {args.action}')


def _validate_skills(args: argparse.Namespace, p, s: Style) -> int:
    validate = p.validate_py
    if not validate.is_file():
        return _die(f'validate.py not found at {validate}')
    targets: list[Path] = []
    if args.name:
        d = p.skills / args.name
        if not d.is_dir():
            return _not_found('skill dir', args.name, _skill_names(p), 'skills list', detail=str(d))
        targets = [d]
    else:
        targets = [d for d in sorted(p.skills.iterdir()) if d.is_dir() and not d.name.startswith('.')]
        if args.limit:
            targets = targets[: args.limit]
    failures = 0
    lines = [header(f'Validate skills ({len(targets)})', s)]
    for d in targets:
        try:
            proc = subprocess.run(
                [sys.executable, str(validate), str(d)],
                capture_output=True,
                text=True,
                timeout=120,
            )
        except subprocess.TimeoutExpired:
            lines.append(s.red(f'TIMEOUT {d.name}'))
            failures += 1
            continue
        out = (proc.stdout or '') + (proc.stderr or '')
        verdict = 'OK'
        for marker in ('VERDICT OK', 'FULL REVIEW REQUIRED', 'HUMAN APPROVAL', 'DO NOT INSTALL'):
            if marker in out:
                verdict = marker
                break
        if proc.returncode != 0 and verdict == 'OK':
            verdict = f'exit={proc.returncode}'
        if 'DO NOT INSTALL' in verdict or 'HUMAN APPROVAL' in verdict or proc.returncode not in (0,):
            # validate.py may exit 0 even on FULL REVIEW
            if 'DO NOT INSTALL' in out or 'HUMAN APPROVAL' in out:
                failures += 1
                lines.append(s.red(f'{verdict:24} {d.name}'))
            elif 'FULL REVIEW' in out:
                lines.append(s.yellow(f'{verdict:24} {d.name}'))
            else:
                lines.append(f'{verdict:24} {d.name}')
        else:
            color = s.green if 'OK' in verdict else s.yellow
            lines.append(f'{color(f"{verdict:24}")} {d.name}')
        if args.verbose and out.strip():
            for line in out.strip().splitlines()[-8:]:
                lines.append(s.dim(f'    {line}'))
    lines.append(hr())
    lines.append(f'failures (approval/block): {failures}')
    _print('\n'.join(str(x) for x in lines))
    return 1 if failures else 0


_EXAMPLE_TIMEOUT_S = 10


def _resolve_command_script(script: str, home: Path) -> Path:
    """Map the `~/.junie/...` tilde path from a command body onto the active Junie home."""
    prefix = '~/.junie/'
    if script.startswith(prefix):
        return home / script[len(prefix):]
    return Path(script).expanduser()


def _check_examples(script: str | None, examples: list[str], home: Path) -> list[dict]:
    """Run `script --check-args <example>` per example in a scratch cwd; never touches real state."""
    results: list[dict] = []
    if not examples:
        return results
    if not script:
        err = 'no python3 ~/.junie/custom/scripts/*.py line in body'
        return [{'text': ex, 'ok': False, 'error': err} for ex in examples]
    path = _resolve_command_script(script, home)
    if not path.is_file():
        return [{'text': ex, 'ok': False, 'error': f'script not found: {path}'} for ex in examples]
    with tempfile.TemporaryDirectory(prefix='agentmgr-examples-') as td:
        for ex in examples:
            try:
                argv = shlex.split(ex)
            except ValueError as err:
                results.append({'text': ex, 'ok': False, 'error': f'unparseable shell words: {err}'})
                continue
            try:
                proc = subprocess.run(
                    [sys.executable, str(path), '--check-args', *argv],
                    cwd=td, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                    check=False, timeout=_EXAMPLE_TIMEOUT_S,
                )
            except subprocess.TimeoutExpired:
                results.append({'text': ex, 'ok': False, 'error': f'timeout after {_EXAMPLE_TIMEOUT_S}s'})
                continue
            if proc.returncode == 0:
                results.append({'text': ex, 'ok': True, 'error': ''})
            else:
                tail = ' '.join((proc.stderr or proc.stdout).strip().splitlines()[-2:])
                results.append({'text': ex, 'ok': False, 'error': f'exit {proc.returncode}: {tail}'})
    return results


def cmd_commands(args: argparse.Namespace) -> int:
    p = _paths(args)
    s = _style(args)
    if args.action in ('list', 'lint'):
        cmds = list_commands(p, query=args.query)
        if args.action == 'lint' or args.json:
            issues = []
            for c in cmds:
                entry = {
                    'name': c.name,
                    'path': str(c.path),
                    'description': c.description,
                    'allowPromptArgument': c.allow_prompt_argument,
                    'required_placeholders': c.required_placeholders,
                    'arg_mode': c.arg_mode,
                    'script': c.script,
                    'examples': [],
                    'ok': True,
                    'problems': [],
                }
                if 'ARGUMENTS' in c.required_placeholders:
                    entry['ok'] = False
                    entry['problems'].append(
                        'required ARGUMENTS placeholder blocks bare /cmd; '
                        'use allowPromptArgument: true and remove the placeholder'
                    )
                if c.required_placeholders and not c.allow_prompt_argument:
                    # not always wrong (explain file=...) but note for CLI wrappers
                    if any(x.lower() in ('arguments', 'args', 'argv') for x in c.required_placeholders):
                        entry['ok'] = False
                        entry['problems'].append('catch-all required placeholder without allowPromptArgument')
                if args.action == 'lint' and not c.allow_prompt_argument and not c.required_placeholders:
                    entry['problems'].append(
                        'no args and allowPromptArgument false — bare /cmd works, but trailing text is dropped'
                    )
                if args.action == 'lint' and args.examples:
                    if not c.examples:
                        entry['problems'].append('no ```text example block — examples not checked')
                    checked = _check_examples(c.script, c.examples, p.home)
                    entry['examples'] = checked
                    for n, r in enumerate(checked, start=1):
                        if not r['ok']:
                            entry['ok'] = False
                            entry['problems'].append(f"example #{n} `{r['text']}` fails: {r['error']}")
                issues.append(entry)
            if args.json:
                if args.action == 'lint':
                    _print(json.dumps(issues, indent=2))
                    return 1 if any(not e['ok'] for e in issues) else 0
                return _print(json.dumps([
                    {k: e[k] for k in ('name', 'path', 'description', 'allowPromptArgument', 'required_placeholders', 'arg_mode')}
                    for e in issues
                ], indent=2))
            # lint text
            lines = [header(f'Command arg lint ({len(issues)})', s)]
            bad = 0
            for e in issues:
                mark = s.green('OK') if e['ok'] and not e['problems'] else (
                    s.red('FAIL') if not e['ok'] else s.yellow('WARN')
                )
                if not e['ok']:
                    bad += 1
                lines.append(f"{mark}  /{e['name']:12}  {e['arg_mode']}")
                if e['examples']:
                    passed = sum(1 for r in e['examples'] if r['ok'])
                    lines.append(s.dim(f"         examples: {passed}/{len(e['examples'])} parse OK"))
                for pr in e['problems']:
                    lines.append(s.dim(f'         - {pr}'))
            lines.append(hr())
            lines.append(f'failures: {bad}')
            _print('\n'.join(str(x) for x in lines))
            return 1 if bad else 0
        return _print(render_commands_cards(cmds, paths=p, style=s))
    if args.action == 'show':
        if not args.name:
            return _die('commands show requires a name')
        name = args.name.lstrip('/')
        path = p.commands / f'{name}.md'
        if not path.is_file():
            return _not_found('command', name, [c.name for c in list_commands(p)], 'commands list')
        out = [render_doc(path, fmt=args.format, max_chars=args.max_chars, style=s)]  # type: ignore[arg-type]
        info = next((c for c in list_commands(p) if c.name == name), None)
        if info and (info.script or info.examples):
            out.append(hr())
            out.append(f'script  : {info.script or "-"}')
            out.append(f'examples: {len(info.examples)} (check: agentmgr commands lint --examples)')
            for ex in info.examples:
                out.append(s.dim(f'  /{name} {ex}'))
        return _print('\n'.join(str(x) for x in out))
    return _die(f'unknown commands action: {args.action}')


# ── config / tune ────────────────────────────────────────────────────────


def cmd_config(args: argparse.Namespace) -> int:
    p = _paths(args)
    s = _style(args)
    if args.action == 'show':
        data = show_config(p, which=args.which)
        if args.json:
            return _print(json.dumps(data, indent=2))
        lines = [header('Config / settings', s)]
        if 'config' in data:
            lines.append(s.bold(f"config ({data.get('config_path')})"))
            lines.append(json.dumps(data['config'], indent=2))
        if 'settings' in data:
            lines.append(hr())
            lines.append(s.bold(f"settings ({data.get('settings_path')})"))
            # redact huge effort blob in pretty mode unless --full
            settings = dict(data['settings'])
            if not args.full and 'effortPerModel' in settings:
                raw = settings['effortPerModel']
                n = 0
                if isinstance(raw, str):
                    try:
                        n = len(json.loads(raw))
                    except json.JSONDecodeError:
                        n = -1
                settings['effortPerModel'] = f'<{n} entries; use tune show or --full>'
            lines.append(json.dumps(settings, indent=2))
        return _print('\n'.join(str(x) for x in lines))
    if args.action == 'get':
        if not args.key:
            return _die('config get requires KEY')
        # search both
        blobs = []
        if args.which in ('both', 'config'):
            blobs.append(('config', show_config(p, 'config')['config']))
        if args.which in ('both', 'settings'):
            blobs.append(('settings', show_config(p, 'settings')['settings']))
        found = False
        all_keys: list[str] = []
        for label, blob in blobs:
            all_keys.extend(_flat_keys(blob))
            try:
                val = get_value(blob, args.key)
                print(f'{label}.{args.key} = {json.dumps(val)}')
                found = True
            except KeyError:
                continue
        if found:
            return 0
        return _not_found('key', args.key, all_keys, 'config show')
    if args.action == 'set':
        if not args.key or args.value is None:
            return _die('config set requires KEY VALUE')
        target = args.which if args.which in ('config', 'settings') else args.target
        if target not in ('config', 'settings'):
            target = _infer_target(args.key)
        try:
            value = coerce_value(args.value)
            result = apply_set(
                target,
                args.key,
                value,
                paths=p,
                dry_run=not args.write,
                force=args.force,
                backup=not args.no_backup,
            )
        except (PermissionError, ValueError, json.JSONDecodeError) as exc:
            return _die(str(exc))
        if args.json:
            return _print(json.dumps(result, indent=2, default=str))
        mode = 'DRY-RUN' if result['dry_run'] else 'WROTE'
        lines = [
            header(f'config set [{mode}]', s),
            kv('target', result['target'], s),
            kv('path', result['path'], s),
            kv('key', result['key'], s),
            kv('old', json.dumps(result['old']), s),
            kv('new', json.dumps(result['new']), s),
        ]
        if result.get('backup'):
            lines.append(kv('backup', result['backup'], s))
        if result['dry_run']:
            lines.append(s.yellow('Re-run with --write to apply.'))
        return _print('\n'.join(str(x) for x in lines))
    return _die(f'unknown config action: {args.action}')


def cmd_tune(args: argparse.Namespace) -> int:
    p = _paths(args)
    s = _style(args)
    if args.action in ('show', None, 'snapshot'):
        snap = tuning_snapshot(p)
        if args.json:
            return _print(json.dumps(snap, indent=2))
        text = render_tuning(snap, s)
        if args.recommend:
            text += '\n' + hr() + '\n' + s.bold('Recommendations') + '\n'
            text += bullet_list(recommend_tuning(snap))
        return _print(text)
    if args.action == 'recommend':
        tips = recommend_tuning(tuning_snapshot(p))
        if args.json:
            return _print(json.dumps(tips, indent=2))
        return _print(header('Tuning recommendations', s) + '\n' + bullet_list(tips))
    if args.action == 'effort':
        model = args.model or args.key
        effort = args.effort or args.value
        if not model or not effort:
            return _die('tune effort requires MODEL EFFORT (or --model/--effort)')
        args.model, args.effort = model, effort
        try:
            result = set_effort(
                args.model,
                args.effort,
                paths=p,
                dry_run=not args.write,
                backup=not args.no_backup,
                force=args.force,
            )
        except (ValueError, PermissionError) as exc:
            return _die(str(exc))
        if args.json:
            return _print(json.dumps(result, indent=2, default=str))
        mode = 'DRY-RUN' if result['dry_run'] else 'WROTE'
        lines = [
            header(f'tune effort [{mode}]', s),
            kv('model', result.get('model'), s),
            kv('old', result.get('effort_old'), s),
            kv('new', result.get('effort_new'), s),
        ]
        if result['dry_run']:
            lines.append(s.yellow('Re-run with --write to apply.'))
        return _print('\n'.join(str(x) for x in lines))
    if args.action == 'set':
        # convenience: tune set token-budget 3000000  → config
        if not args.key or args.value is None:
            return _die('tune set requires KEY VALUE')
        key = args.key
        target = _infer_target(key)
        try:
            value = coerce_value(args.value)
            result = apply_set(
                target,
                key,
                value,
                paths=p,
                dry_run=not args.write,
                force=args.force,
                backup=not args.no_backup,
            )
        except (PermissionError, ValueError, json.JSONDecodeError) as exc:
            return _die(str(exc))
        if args.json:
            return _print(json.dumps(result, indent=2, default=str))
        mode = 'DRY-RUN' if result['dry_run'] else 'WROTE'
        return _print(
            f'[{mode}] {result["target"]}.{result["key"]}: '
            f'{json.dumps(result["old"])} -> {json.dumps(result["new"])}'
            + ('' if not result['dry_run'] else '  (pass --write to apply)')
        )
    return _die(f'unknown tune action: {args.action}')


# ── steer ────────────────────────────────────────────────────────────────


def cmd_steer(args: argparse.Namespace) -> int:
    p = _paths(args)
    s = _style(args)
    if args.action == 'templates':
        names = list_templates()
        if args.json:
            return _print(json.dumps(names, indent=2))
        lines = [header('Steering / routing templates', s)]
        for n in names:
            lines.append(f'  • {n}')
        return _print('\n'.join(lines))
    if args.action == 'show':
        if not args.name:
            return _die('steer show requires template name')
        try:
            body = get_template(args.name)
        except KeyError:
            return _not_found('template', args.name, list_templates(), 'steer templates')
        return _print(header(f'Template: {args.name}', s) + '\n' + body)
    if args.action == 'scan':
        roots = [Path(args.root)] if args.root else default_scan_roots(p)
        blocks = []
        for r in roots:
            blocks.extend(scan_routing_blocks(r))
        if args.json:
            data = [
                {'file': b.file, 'line': b.line, 'primitives': b.primitives, 'preview': b.preview}
                for b in blocks
            ]
            return _print(json.dumps(data, indent=2))
        return _print(render_routing_report(blocks, s))
    if args.action == 'scaffold':
        templates = args.templates or ['domain-routing', 'project-over-global', 'decision-matrix']
        name = args.name or 'steering'
        out = Path(args.output) if args.output else Path('/tmp') / f'agentmgr-steer-{name}.md'
        try:
            body = scaffold_steering_doc(name, templates, out, dry_run=not args.write)
        except (KeyError, FileExistsError) as exc:
            return _die(str(exc))
        if args.write:
            print(f'Wrote {out}', file=sys.stderr)
        return _print(body)
    return _die(f'unknown steer action: {args.action}')


# ── workflow / sadkitti / test ───────────────────────────────────────────


def cmd_workflow(args: argparse.Namespace) -> int:
    p = _paths(args)
    spec = args.events or 'latest'
    try:
        text = run_audit(spec, p, mermaid=args.mermaid, as_json=args.json)
    except FileNotFoundError as exc:
        return _die(str(exc), code=1)
    return _print(text)


def cmd_sadkitti(args: argparse.Namespace) -> int:
    root = Path(args.directory).expanduser().resolve() if args.directory else Path.cwd()
    if args.action == 'scan':
        found = sk.scan(root)
        if args.json:
            return _print(json.dumps(found, indent=2))
        return _print(sk.format_scan(found))
    if args.action == 'lint':
        errors = sk.lint(root)
        if args.json:
            payload = {'ok': not errors, 'errors': errors}
            print(json.dumps(payload, indent=2))
            return 1 if errors else 0
        text, code = sk.format_lint(errors)
        print(text)
        return code
    if args.action == 'graph':
        graph = sk.build_graph(root)
        if args.mermaid:
            return _print(sk.build_mermaid(graph))
        if args.plantuml:
            return _print(sk.build_plantuml(graph))
        if args.png:
            try:
                sk.render_image(graph, 'png', Path(args.png))
            except RuntimeError as exc:
                return _die(str(exc), 1)
            print(f'Graph written to {args.png}')
            return 0
        if args.svg:
            try:
                sk.render_image(graph, 'svg', Path(args.svg))
            except RuntimeError as exc:
                return _die(str(exc), 1)
            print(f'Graph written to {args.svg}')
            return 0
        if args.pandoc:
            try:
                sk.render_via_pandoc(graph, Path(args.pandoc))
            except RuntimeError as exc:
                return _die(str(exc), 1)
            print(f'Graph written to {args.pandoc}')
            return 0
        if args.json:
            serial = {k: sorted(v) for k, v in graph.items()}
            return _print(json.dumps(serial, indent=2))
        return _print(sk.format_graph_text(graph, root))
    return _die(f'unknown sadkitti action: {args.action}')


def cmd_test(args: argparse.Namespace) -> int:
    """Run a combined workflow + sadkitti health check."""
    p = _paths(args)
    s = _style(args)
    lines = [header('Agent workflow test suite', s)]
    code = 0

    # 1) sadkitti lint on target directory
    root = Path(args.directory).expanduser().resolve() if args.directory else p.custom_docs
    lines.append(s.bold(f'sadkitti lint — {root}'))
    errors = sk.lint(root)
    text, lint_code = sk.format_lint(errors)
    lines.append(text)
    if lint_code:
        code = 1

    # 2) scan count
    found = sk.scan(root)
    lines.append(kv('sadkitti blocks', len(found), s))

    # 3) graph summary
    graph = sk.build_graph(root)
    edge_count = sum(len(v) for v in graph.values())
    lines.append(kv('graph edges', edge_count, s))

    # 4) optional workflow audit
    if args.events:
        lines.append(hr())
        lines.append(s.bold('workflow audit'))
        try:
            lines.append(run_audit(args.events, p, mermaid=args.mermaid, as_json=False))
        except FileNotFoundError as exc:
            lines.append(s.red(str(exc)))
            code = 1

    # 5) quick skill inventory sanity
    skills = list_skills(p)
    missing = [sk_.name for sk_ in skills if not sk_.has_skill_md]
    lines.append(hr())
    lines.append(kv('skills', len(skills), s))
    if missing:
        lines.append(s.yellow(f'skills missing SKILL.md: {", ".join(missing[:10])}'))
        code = 1
    else:
        lines.append(s.green('all skill dirs have SKILL.md'))

    _print('\n'.join(str(x) for x in lines))
    return code


def cmd_mcp(args: argparse.Namespace) -> int:
    p = _paths(args)
    s = _style(args)
    mcp = load_mcp(p)
    servers = mcp.get('mcpServers') or {}
    if args.json:
        return _print(json.dumps(mcp, indent=2))
    lines = [header(f'MCP servers ({len(servers)})', s), kv('path', p.mcp, s), hr()]
    for name, cfg in sorted(servers.items()):
        if not isinstance(cfg, dict):
            lines.append(f'{name}: {cfg!r}')
            continue
        en = cfg.get('enabled', True)
        mark = s.green('on ') if en is not False else s.red('off')
        lines.append(f'{mark} {s.bold(name)}')
        lines.append(f'     cmd: {cfg.get("command")}')
        if cfg.get('args'):
            lines.append(f'     args: {cfg.get("args")}')
    return _print('\n'.join(str(x) for x in lines))


def cmd_models(args: argparse.Namespace) -> int:
    p = _paths(args)
    s = _style(args)
    models = list_models(p)
    if args.json:
        data = [{'file': m.file_stem, **m.data} for m in models]
        return _print(json.dumps(data, indent=2))
    rows = []
    for m in models:
        rows.append(
            (
                m.file_stem,
                str(m.data.get('id', '-')),
                str(m.data.get('apiType', '-')),
                str(m.data.get('baseUrl', '-'))[:40],
            )
        )
    return _print(header(f'Models ({len(models)})', s) + '\n' + table(rows, headers=('file', 'id', 'api', 'baseUrl')))


# ── argparse ─────────────────────────────────────────────────────────────


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog='agentmgr',
        description='Advanced Junie agent management (docs, tune, steer, workflow tests).',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  agentmgr status
  agentmgr docs show agents --format toc
  agentmgr docs index
  agentmgr skills list --query kamailio
  agentmgr tune show --recommend
  agentmgr config set token-budget 3000000 --which config   # dry-run
  agentmgr config set token-budget 3000000 --which config --write
  agentmgr steer templates
  agentmgr steer scan --root ~/.junie
  agentmgr sadkitti lint ~/.junie/custom/docs
  agentmgr sadkitti graph ~/.junie --mermaid
  agentmgr workflow audit latest --mermaid
  agentmgr test --directory ~/.junie/custom/docs --events latest
''',
    )
    parser.add_argument('--junie-home', default=None, help='Override JUNIE_HOME (default ~/.junie)')
    parser.add_argument('--json', action='store_true', help='JSON output where supported')
    parser.add_argument('--no-color', action='store_true')
    parser.add_argument('--color', action='store_true')
    parser.add_argument(
        '--check-args',
        action='store_true',
        help='Parse argv, print the resolved namespace as JSON and exit 0 (no filesystem access)',
    )

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument('--junie-home', default=argparse.SUPPRESS, help='Override JUNIE_HOME (default ~/.junie)')
    common.add_argument('--json', action='store_true', default=argparse.SUPPRESS, help='JSON output where supported')
    common.add_argument('--no-color', action='store_true', default=argparse.SUPPRESS)
    common.add_argument('--color', action='store_true', default=argparse.SUPPRESS)

    sub = parser.add_subparsers(dest='cmd', required=True)

    def add(name: str, help_: str, examples: Sequence[str], extra: str = '') -> argparse.ArgumentParser:
        epilog = extra + 'Examples:\n' + ''.join(f'  agentmgr {e}\n' for e in examples)
        return sub.add_parser(
            name,
            help=help_,
            parents=[common],
            formatter_class=argparse.RawDescriptionHelpFormatter,
            epilog=epilog,
        )

    # status
    p_status = add('status', 'Overview of agent home', ['status', 'status --json'])
    p_status.set_defaults(func=cmd_status)

    p_paths = add('paths', 'Print resolved paths', ['paths', 'paths --json'])
    p_paths.set_defaults(func=cmd_paths)

    p_inv = add('inventory', 'Inventory docs/skills/commands/models/mcp', ['inventory', 'inventory skills --limit 10'])
    p_inv.add_argument(
        'what',
        nargs='?',
        default='all',
        choices=['all', 'docs', 'skills', 'commands', 'models', 'mcp'],
    )
    p_inv.add_argument('--limit', type=int, default=0)
    p_inv.set_defaults(func=cmd_inventory)

    # docs
    p_docs = add('docs', 'Pretty-print agent documentation', ['docs index', 'docs list', 'docs show agents --format toc'])
    p_docs.add_argument(
        'action',
        nargs='?',
        default='index',
        choices=['show', 'list', 'tree', 'index'],
    )
    p_docs.add_argument('target', nargs='?', help='agents|guidelines|skill:NAME|path|…')
    p_docs.add_argument(
        '--format',
        default='pretty',
        choices=['pretty', 'toc', 'outline', 'raw', 'cards'],
    )
    p_docs.add_argument('--max-chars', type=int, default=12000)
    p_docs.add_argument('--no-skills', action='store_true')
    p_docs.add_argument('--no-commands', action='store_true')
    p_docs.set_defaults(func=cmd_docs)

    # skills
    p_sk = add('skills', 'List/show/validate skills', ['skills list -q kamailio', 'skills show NAME', 'skills validate NAME'])
    p_sk.add_argument('action', choices=['list', 'show', 'validate'])
    p_sk.add_argument('name', nargs='?', help='Skill name for show/validate')
    p_sk.add_argument('--query', '-q')
    p_sk.add_argument('--limit', type=int, default=0)
    p_sk.add_argument('--format', default='pretty', choices=['pretty', 'toc', 'outline', 'raw'])
    p_sk.add_argument('--max-chars', type=int, default=12000)
    p_sk.add_argument('--verbose', '-v', action='store_true')
    p_sk.set_defaults(func=cmd_skills)

    # commands
    p_cmd = add('commands', 'List/show/lint custom commands', ['commands list', 'commands show agentmgr', 'commands lint --examples -q agentmgr'])
    p_cmd.add_argument('action', choices=['list', 'show', 'lint'])
    p_cmd.add_argument('name', nargs='?')
    p_cmd.add_argument('--query', '-q')
    p_cmd.add_argument('--format', default='pretty', choices=['pretty', 'toc', 'outline', 'raw'])
    p_cmd.add_argument('--max-chars', type=int, default=12000)
    p_cmd.add_argument(
        '--examples',
        action='store_true',
        help='With lint: run each ```text example through `<script> --check-args`',
    )
    p_cmd.set_defaults(func=cmd_commands)

    # config
    p_cfg = add('config', 'Show/get/set config.json and settings.json', ['config show --which config', 'config get token-budget', 'config set token-budget 3000000 --which config --write --no-backup'])
    p_cfg.add_argument('action', choices=['show', 'get', 'set'])
    p_cfg.add_argument('key', nargs='?')
    p_cfg.add_argument('value', nargs='?')
    p_cfg.add_argument(
        '--which',
        default='both',
        choices=['both', 'config', 'settings'],
        help='Which file (set infers settings/config from KEY when omitted)',
    )
    p_cfg.add_argument('--target', choices=['config', 'settings'], help=argparse.SUPPRESS)
    p_cfg.add_argument('--write', action='store_true', help='Apply change (default is dry-run)')
    p_cfg.add_argument('--force', action='store_true')
    p_cfg.add_argument('--no-backup', action='store_true')
    p_cfg.add_argument('--full', action='store_true', help='Do not summarize effortPerModel')
    p_cfg.set_defaults(func=cmd_config)

    # tune
    p_tune = add(
        'tune',
        'Agent tuning snapshot and adjustments',
        [
            'tune show --recommend',
            'tune set token-budget 3000000 --write --no-backup',
            'tune set model MODEL --json',
            'tune effort MODEL low --write',
        ],
        extra=(
            'tune set KEY mapping:\n'
            '  settings.json: model, modelForLaunch, braveMode, subagentsMode, ecoMode,\n'
            '                 eventDensityMode, diffViewMode, provider\n'
            '  config.json  : token-budget, time-limit, brave, auto-update, and any other key\n'
            'Writes back up to <file dir>/.agentmgr-backups/ unless --no-backup.\n\n'
        ),
    )
    p_tune.add_argument(
        'action',
        nargs='?',
        default='show',
        choices=['show', 'snapshot', 'recommend', 'effort', 'set'],
    )
    p_tune.add_argument('key', nargs='?', help='For set: key name')
    p_tune.add_argument('value', nargs='?', help='For set: value')
    p_tune.add_argument('--model', help='For effort: model id')
    p_tune.add_argument('--effort', help='none|low|medium|high')
    p_tune.add_argument('--write', action='store_true')
    p_tune.add_argument('--force', action='store_true')
    p_tune.add_argument('--no-backup', action='store_true', help='Skip .agentmgr-backups/ copy on --write')
    p_tune.add_argument('--recommend', action='store_true', help='With show: append tips')
    p_tune.set_defaults(func=cmd_tune)

    # steer
    p_steer = add('steer', 'Logic steering / decision-routing helpers', ['steer templates', 'steer show domain-routing', 'steer scan --root ~/.junie'])
    p_steer.add_argument('action', choices=['templates', 'show', 'scan', 'scaffold'])
    p_steer.add_argument('name', nargs='?', help='Template or scaffold name')
    p_steer.add_argument('--root', help='Scan root (default: AGENTS.md + custom/docs)')
    p_steer.add_argument(
        '--templates',
        nargs='+',
        help='Template names for scaffold',
    )
    p_steer.add_argument('--output', '-o', help='Scaffold output path')
    p_steer.add_argument('--write', action='store_true', help='Write scaffold (default print only)')
    p_steer.set_defaults(func=cmd_steer)

    # workflow
    p_wf = add('workflow', 'Audit session workflow / tokens from events.jsonl', ['workflow audit latest', 'workflow audit latest --mermaid'])
    p_wf.add_argument('action', nargs='?', default='audit', choices=['audit'])
    p_wf.add_argument('events', nargs='?', default='latest', help='path | session-id | latest')
    p_wf.add_argument('--mermaid', action='store_true')
    p_wf.set_defaults(func=cmd_workflow)

    # sadkitti
    p_sad = add('sadkitti', 'SAD KITTI scan / lint / graph', ['sadkitti lint ~/.junie/custom/docs', 'sadkitti graph ~/.junie --mermaid'])
    p_sad.add_argument('action', choices=['scan', 'lint', 'graph'])
    p_sad.add_argument('directory', nargs='?', default='.')
    p_sad.add_argument('--plantuml', action='store_true')
    p_sad.add_argument('--mermaid', action='store_true')
    p_sad.add_argument('--png')
    p_sad.add_argument('--svg')
    p_sad.add_argument('--pandoc')
    p_sad.set_defaults(func=cmd_sadkitti)

    # test
    p_test = add('test', 'Combined sadkitti + optional workflow health check', ['test', 'test --directory ~/.junie/custom/docs --events latest'])
    p_test.add_argument('--directory', '-d', help='Docs root to lint (default: custom/docs)')
    p_test.add_argument('--events', help='events path/session/latest for workflow audit')
    p_test.add_argument('--mermaid', action='store_true')
    p_test.set_defaults(func=cmd_test)

    # mcp / models
    p_mcp = add('mcp', 'List MCP servers', ['mcp', 'mcp --json'])
    p_mcp.set_defaults(func=cmd_mcp)

    p_models = add('models', 'List model configs', ['models', 'models --json'])
    p_models.set_defaults(func=cmd_models)

    return parser


def _normalize_argv(argv: Sequence[str] | None) -> list[str]:
    """Default bare invocation to ``status`` so wrappers/PATH shims and slash commands work."""
    if argv is None:
        argv_list = list(sys.argv[1:])
    else:
        argv_list = list(argv)
    # Strip global flags; if no subcommand token remains, inject default.
    globals_with_val = {'--junie-home'}
    globals_bool = {'--json', '--no-color', '--color', '--check-args', '-h', '--help'}
    i = 0
    saw_cmd = False
    while i < len(argv_list):
        tok = argv_list[i]
        if tok in globals_bool:
            if tok in ('-h', '--help'):
                return argv_list  # let argparse show help
            i += 1
            continue
        if tok in globals_with_val:
            i += 2
            continue
        if tok.startswith('--junie-home='):
            i += 1
            continue
        saw_cmd = True
        break
    if not saw_cmd:
        argv_list.append('status')
    return argv_list


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(_normalize_argv(argv))
    if args.check_args:
        print(json.dumps({k: v for k, v in vars(args).items() if k != 'func'}, default=str))
        return 0
    try:
        return int(args.func(args) or 0)
    except BrokenPipeError:
        try:
            sys.stdout.close()
        except Exception:
            pass
        return 0
    except KeyboardInterrupt:
        return 130


if __name__ == '__main__':
    raise SystemExit(main())
