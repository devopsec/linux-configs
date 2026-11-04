#!/usr/bin/env python3
"""
histmgr — Junie session history manager / skill-miner helper.

Catalog, filter, mine reusable workflows from ~/.junie/sessions, and
optionally delete sessions. Designed for agent + human use (arg-based;
interactive prompts when stdin is a TTY and flags omit choices).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

DEFAULT_JUNIE_HOME = Path(os.environ.get('JUNIE_HOME', Path.home() / '.junie'))
SESSIONS_DIRNAME = 'sessions'
INDEX_NAME = 'index.jsonl'

# Recurring workflow detectors → candidate skill/command names
# id, kind(skill|command|either), suggested_name, regex
PATTERN_RULES: list[tuple[str, str, str, re.Pattern[str]]] = [
    ('todo_implement', 'skill', 'dev-project-todo-implement',
     re.compile(r'todo-[a-f0-9]+|implement\s+`?todo|trackers/todo|FIXME|close this todo', re.I)),
    ('commit_message', 'skill', 'vcs-git-commit-create',
     re.compile(r'commit message|staged changes|conventional commit|summarize the pending|do not change the git state', re.I)),
    ('fix_from_logs', 'skill', 'dev-project-fixIssue-fromLogs',
     re.compile(
         r'clion-build|cmake.*log|fix the build errors|ninja: error|journalctl|condensed-errors|triage these logs|system doctor',
         re.I,
     )),
    ('kamailio', 'skill', 'dev-kamailio-platform-manage',
     re.compile(r'kamailio|dsiprouter|modparam|pike|rate.?limit|kamcmd|kamctl', re.I)),
    ('spec_implement', 'skill', 'dev-project-spec-implement',
     re.compile(r'\.docx|interface.control|openapi|asyncapi|\.proto\b|implement from (the )?spec|requirements matrix', re.I)),
    ('editor_config', 'skill', 'dev-editor-config-manage',
     re.compile(r'\bneovim\b|\bnvim\b|\bvimrc\b|vimpager|nvimpager|\bemacs\b|\bzed\b|\bmicro\b', re.I)),
    ('agents_bootstrap', 'skill', 'docs-agents-project-bootstrap',
     re.compile(r'agents\.md|sad.?kitti|agent instructions|parent documentation|bootstrap.*agent', re.I)),
    ('docs_update', 'skill', 'docs-project-documentation-update',
     re.compile(r'update the readme|organize.*documentation|outdated docs|documentation drift|sync readme', re.I)),
    ('skill_author', 'skill', 'dev-agents-skill-create',
     re.compile(r'create a skill|agent skill|~/.junie/skills|update.*skill', re.I)),
    ('session_mine', 'command', 'histmgr',
     re.compile(r'session history|reusable (logic|workflow)|skill.?mine|/histmgr', re.I)),
    ('sectool', 'command', 'sectool',
     re.compile(r'/sectool|security tools|sectools/', re.I)),
    ('agentmgr', 'command', 'agentmgr',
     re.compile(r'/agentmgr|agent management|tune (the )?agent|sadkitti (lint|scan|graph)|workflow audit', re.I)),
    ('terraform', 'skill', 'infra-terraform-any-manage',
     re.compile(r'\bterraform\b|\bopentofu\b|terraform\.tf|\.tfvars\b', re.I)),
    ('bash_script', 'skill', 'dev-bash-script-review',
     re.compile(r'bash guideline|shell script|review\s+(the\s+)?(bash|shell)|\.sh\b.*\breview\b|audit.*\bbash\b', re.I)),
    ('bash_utility', 'skill', 'dev-bash-utility-create',
     re.compile(r'bash (helper|utility|library)|shared bash|reusable bash', re.I)),
    ('github_pr', 'skill', 'vcs-forge-pr-create',
     re.compile(r'\bpull request\b|\bopen a pr\b|create a pr\b|gh pr create|forge pr create|gcli (pulls|pr) create', re.I)),
    ('forge_cli', 'skill', 'vcs-forge-any-manage',
     re.compile(r'\bforge (pr|issue|ci|api|release|milestone|label|auth|repo)\b|git-pkgs/forge|\bgh (pr|issue|run|api|repo|release)\b', re.I)),
    ('gcli', 'skill', 'vcs-gcli-any-manage',
     re.compile(r'\bgcli\b|herrhotzenplotz|bugzilla', re.I)),
    ('docx_edit', 'skill', 'docs-docx-document-edit',
     re.compile(r'edit.*\.docx|docx (layout|document)', re.I)),
    ('notion', 'skill', 'docs-notion-knowledge-capture',
     re.compile(r'\bnotion\b', re.I)),
    ('playwright', 'skill', 'web-playwright-webapp-test',
     re.compile(r'\bplaywright\b|e2e test|browser automat', re.I)),
    ('threat_model', 'skill', 'sec-dev-threatModel-create',
     re.compile(r'threat model|abuse path|stride', re.I)),
    ('frontend_ui', 'skill', 'web-frontend-ui-create',
     re.compile(r'landing page|react component|frontend ui|beautify.*(ui|page)', re.I)),
]


@dataclass
class SessionRow:
    session_id: str
    task_name: str | None
    project_dir: str | None
    status: str | None
    created_at: int | None
    updated_at: int | None
    transcript_size: int = 0
    path: Path | None = None
    tags: list[str] = field(default_factory=list)

    @property
    def sort_ts(self) -> int:
        return int(self.updated_at or self.created_at or 0)

    def when(self) -> str:
        ts = self.sort_ts
        if not ts:
            return '?'
        return datetime.fromtimestamp(ts / 1000, tz=timezone.utc).astimezone().strftime('%Y-%m-%d %H:%M')


def junie_home() -> Path:
    return Path(os.environ.get('JUNIE_HOME', DEFAULT_JUNIE_HOME)).expanduser().resolve()


def sessions_root(home: Path | None = None) -> Path:
    return (home or junie_home()) / SESSIONS_DIRNAME


def current_session_ids() -> set[str]:
    """Best-effort detection of the live session — never delete these."""
    found: set[str] = set()
    for key in ('JUNIE_SESSION_ID', 'JUNIE_SESSION', 'JUNIE_CURRENT_SESSION'):
        val = os.environ.get(key)
        if val:
            found.add(Path(val).name)
    # Active scratch: /tmp/junie/session-<id>/ — keep only newest by mtime
    tmp = Path('/tmp/junie')
    if tmp.is_dir():
        scratch = [c for c in tmp.iterdir() if c.is_dir() and c.name.startswith('session-')]
        if scratch:
            newest = max(scratch, key=lambda p: p.stat().st_mtime_ns)
            found.add(newest.name)
    # CWD under sessions/
    try:
        cwd = Path.cwd().resolve()
        root = sessions_root().resolve()
        if root in cwd.parents or cwd == root:
            rel = cwd.relative_to(root)
            if rel.parts:
                found.add(rel.parts[0])
    except (OSError, ValueError):
        pass
    return found


def load_index(root: Path) -> list[SessionRow]:
    rows: list[SessionRow] = []
    index_path = root / INDEX_NAME
    by_id: dict[str, dict[str, Any]] = {}
    if index_path.is_file():
        with index_path.open(encoding='utf-8', errors='replace') as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                sid = obj.get('sessionId')
                if not sid:
                    continue
                by_id[sid] = obj

    if root.is_dir():
        for child in root.iterdir():
            if not child.is_dir() or child.name.startswith('.'):
                continue
            if child.name == INDEX_NAME:
                continue
            sid = child.name
            meta = by_id.pop(sid, {})
            tpath = child / 'transcript.md'
            try:
                tsize = tpath.stat().st_size if tpath.is_file() else 0
            except OSError:
                tsize = 0
            rows.append(
                SessionRow(
                    session_id=sid,
                    task_name=meta.get('taskName'),
                    project_dir=meta.get('projectDir'),
                    status=meta.get('status'),
                    created_at=meta.get('createdAt'),
                    updated_at=meta.get('updatedAt'),
                    transcript_size=tsize,
                    path=child,
                )
            )
        for sid, meta in by_id.items():
            rows.append(
                SessionRow(
                    session_id=sid,
                    task_name=meta.get('taskName'),
                    project_dir=meta.get('projectDir'),
                    status=meta.get('status'),
                    created_at=meta.get('createdAt'),
                    updated_at=meta.get('updatedAt'),
                    transcript_size=0,
                    path=None,
                )
            )

    rows.sort(key=lambda r: r.sort_ts, reverse=True)
    return rows


def read_transcript_head(path: Path | None, limit: int = 8000) -> str:
    if not path:
        return ''
    t = path / 'transcript.md'
    if not t.is_file():
        return ''
    try:
        return t.read_text(encoding='utf-8', errors='replace')[:limit]
    except OSError:
        return ''


def _compile_query(query: str) -> re.Pattern[str]:
    try:
        return re.compile(query, re.I)
    except re.error as e:
        raise SystemExit(f'Invalid --query regex: {e}') from e


def _parse_day_ms(day: str, *, end_of_day: bool = False) -> float:
    try:
        dt = datetime.strptime(day, '%Y-%m-%d')
    except ValueError as e:
        raise SystemExit(f'Invalid date (use YYYY-MM-DD): {e}') from e
    if end_of_day:
        # inclusive until end of local calendar day → compare in ms
        dt = dt.replace(hour=23, minute=59, second=59)
    return dt.timestamp() * 1000


def apply_filters(
    rows: Iterable[SessionRow],
    *,
    project: str | None = None,
    query: str | None = None,
    since: str | None = None,
    until: str | None = None,
    tag: str | None = None,
    status: str | None = None,
    min_transcript_kb: int | None = None,
    limit: int | None = None,
) -> list[SessionRow]:
    out = list(rows)
    if project:
        p = project.lower()
        out = [r for r in out if r.project_dir and p in r.project_dir.lower()]
    if query:
        q = _compile_query(query)
        filtered: list[SessionRow] = []
        for r in out:
            blob = f'{r.task_name or ""} {r.project_dir or ""} {r.session_id} {r.status or ""}'
            if q.search(blob):
                filtered.append(r)
                continue
            head = read_transcript_head(r.path, 4000)
            if head and q.search(head):
                filtered.append(r)
        out = filtered
    if since:
        thr = _parse_day_ms(since, end_of_day=False)
        # Undated sessions (sort_ts==0) are excluded from date filters
        out = [r for r in out if r.sort_ts and r.sort_ts >= thr]
    if until:
        thr = _parse_day_ms(until, end_of_day=True)
        out = [r for r in out if r.sort_ts and r.sort_ts <= thr]
    if min_transcript_kb is not None:
        thr_b = min_transcript_kb * 1024
        out = [r for r in out if r.transcript_size >= thr_b]
    if status:
        s = status.lower()
        out = [r for r in out if (r.status or '').lower() == s]
    if tag:
        for r in out:
            if not r.tags:
                r.tags = detect_tags(r)
        out = [r for r in out if tag in r.tags]
    if limit is not None and limit >= 0:
        out = out[:limit]
    return out


def detect_tags(row: SessionRow) -> list[str]:
    blob = f'{row.task_name or ""}\n{read_transcript_head(row.path, 6000)}'
    tags = [pid for pid, _kind, _name, cre in PATTERN_RULES if cre.search(blob)]
    return tags or ['other']


def existing_artifacts() -> tuple[set[str], set[str]]:
    skills: set[str] = set()
    commands: set[str] = set()
    skills_dir = junie_home() / 'skills'
    if skills_dir.is_dir():
        skills = {p.name for p in skills_dir.iterdir() if p.is_dir()}
    commands_dir = junie_home() / 'commands'
    if commands_dir.is_dir():
        commands = {p.stem for p in commands_dir.glob('*.md')}
    return skills, commands


def annotate_existence(candidates: list[dict[str, Any]]) -> None:
    skills, commands = existing_artifacts()
    for c in candidates:
        name = c['suggested_name']
        kind = c['kind']
        if kind == 'command':
            c['already_exists'] = name in commands
        elif kind == 'skill':
            c['already_exists'] = name in skills
        else:
            c['already_exists'] = name in skills or name in commands
        c['create_as'] = 'skill' if kind == 'either' else kind


def cmd_list(args: argparse.Namespace) -> int:
    root = sessions_root()
    rows = apply_filters(
        load_index(root),
        project=args.project,
        query=args.query,
        since=args.since,
        until=args.until,
        tag=args.tag,
        status=args.status,
        min_transcript_kb=args.min_kb,
        limit=args.limit,
    )
    if args.json:
        payload = [
            {
                'sessionId': r.session_id,
                'taskName': r.task_name,
                'projectDir': r.project_dir,
                'status': r.status,
                'updatedAt': r.updated_at,
                'when': r.when(),
                'transcriptBytes': r.transcript_size,
                'tags': r.tags or detect_tags(r),
            }
            for r in rows
        ]
        json.dump(payload, sys.stdout, indent=2)
        print()
        return 0

    print(f'sessions_root={root}  count={len(rows)}')
    print(f'{"WHEN":<16} {"KB":>5}  {"SESSION_ID":<32}  PROJECT  TASK')
    for r in rows:
        proj = (r.project_dir or '').replace(str(Path.home()), '~')
        if len(proj) > 40:
            proj = '…' + proj[-39:]
        task = (r.task_name or '(untitled)')[:50]
        print(f'{r.when():<16} {r.transcript_size // 1024:>5}  {r.session_id:<32}  {proj}  {task}')
    return 0


def cmd_show(args: argparse.Namespace) -> int:
    root = sessions_root()
    sid = args.session_id
    path = root / sid
    if not path.is_dir():
        print(f'Session not found: {sid}', file=sys.stderr)
        return 1
    meta: dict[str, Any] = {'sessionId': sid}
    index = root / INDEX_NAME
    if index.is_file():
        with index.open(encoding='utf-8', errors='replace') as fh:
            for line in fh:
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if obj.get('sessionId') == sid:
                    meta = obj
                    break
    row = SessionRow(
        session_id=sid,
        task_name=meta.get('taskName'),
        project_dir=meta.get('projectDir'),
        status=meta.get('status'),
        created_at=meta.get('createdAt'),
        updated_at=meta.get('updatedAt'),
        path=path,
    )
    meta['tags'] = detect_tags(row)
    meta['when'] = row.when()
    print(json.dumps(meta, indent=2))
    t = path / 'transcript.md'
    if args.transcript and t.is_file():
        text = t.read_text(encoding='utf-8', errors='replace')
        if args.max_chars and len(text) > args.max_chars:
            print(text[: args.max_chars])
            print(f'\n… truncated at {args.max_chars} chars')
        else:
            print(text)
    else:
        size = t.stat().st_size if t.is_file() else 0
        print(f'transcript: {t if t.is_file() else "missing"} size={size}')
    return 0


def mine_candidates(rows: list[SessionRow]) -> list[dict[str, Any]]:
    buckets: dict[str, dict[str, Any]] = {}
    for pid, kind, name, _cre in PATTERN_RULES:
        buckets[pid] = {
            'id': pid,
            'kind': kind,
            'suggested_name': name,
            'count': 0,
            'examples': [],
        }
    for r in rows:
        blob = f'{r.task_name or ""}\n{read_transcript_head(r.path, 6000)}'
        for pid, _kind, _name, cre in PATTERN_RULES:
            if cre.search(blob):
                b = buckets[pid]
                b['count'] += 1
                if len(b['examples']) < 5:
                    b['examples'].append(
                        {
                            'sessionId': r.session_id,
                            'taskName': r.task_name,
                            'projectDir': r.project_dir,
                            'when': r.when(),
                        }
                    )
    ranked = sorted(buckets.values(), key=lambda x: x['count'], reverse=True)
    return [b for b in ranked if b['count'] > 0]


def _selection_payload(selected: list[dict[str, Any]], guidance: str) -> dict[str, Any]:
    return {
        'selected': selected,
        'guidance': guidance,
        'instruction': (
            'Create or update the selected agent skills/commands using '
            'dev-agents-skill-create for skills and ~/.junie/commands/<name>.md for commands. '
            'Honor optional guidance. Do not overwrite without explicit approval.'
        ),
    }


def interactive_choose(candidates: list[dict[str, Any]], guidance: str) -> int:
    print('Interactive select — one line per batch; empty line finishes.')
    print('Format: <num>[,num…] [skill|command]  optional notes after #')
    selected: list[dict[str, Any]] = []
    notes_acc: list[str] = []
    while True:
        try:
            line = input('> ').strip()
        except EOFError:
            break
        if not line:
            break
        notes = ''
        if '#' in line:
            line, notes = line.split('#', 1)
            notes = notes.strip()
            if notes:
                notes_acc.append(notes)
        parts = line.split()
        if not parts:
            continue
        ids_part = parts[0]
        as_kind = parts[1] if len(parts) > 1 else None
        nums: list[int] = []
        for tok in ids_part.split(','):
            tok = tok.strip()
            if tok.isdigit():
                nums.append(int(tok))
        for n in nums:
            if 1 <= n <= len(candidates):
                c = dict(candidates[n - 1])
                if as_kind in {'skill', 'command'}:
                    c['create_as'] = as_kind
                # de-dupe by id
                if not any(s.get('id') == c.get('id') for s in selected):
                    selected.append(c)
    if not selected:
        print('No selection.')
        return 0
    g = ' | '.join(x for x in [guidance, *notes_acc] if x)
    payload = _selection_payload(selected, g)
    out = Path('/tmp') / f'histmgr-selection-{os.getpid()}.json'
    out.write_text(json.dumps(payload, indent=2), encoding='utf-8')
    print(json.dumps(payload, indent=2))
    print(f'Wrote {out}')
    return 0


def cmd_mine(args: argparse.Namespace) -> int:
    root = sessions_root()
    rows = apply_filters(
        load_index(root),
        project=args.project,
        query=args.query,
        since=args.since,
        until=args.until,
        tag=args.tag,
        status=args.status,
        min_transcript_kb=args.min_kb,
        limit=None,
    )
    candidates = mine_candidates(rows)
    annotate_existence(candidates)
    if args.min_hits and args.min_hits > 1:
        candidates = [c for c in candidates if c['count'] >= args.min_hits]
    if args.exclude_existing:
        candidates = [c for c in candidates if not c.get('already_exists')]
    if args.limit:
        candidates = candidates[: args.limit]

    guidance = args.guidance or ''

    if args.json:
        json.dump({'candidates': candidates, 'guidance': guidance, 'session_count': len(rows)}, sys.stdout, indent=2)
        print()
        return 0

    print(f'Mined {len(candidates)} candidate patterns from {len(rows)} sessions ({root})')
    if guidance:
        print(f'Extra guidance: {guidance}')
    print()
    for i, c in enumerate(candidates, 1):
        exists = 'EXISTS' if c['already_exists'] else 'new'
        print(f'{i:2d}. [{c["count"]:3d} hits] {c["suggested_name"]}  ({c["kind"]}, {exists})')
        for ex in c['examples'][:3]:
            print(f'      - {ex["when"]} {ex["sessionId"]}  {ex.get("taskName") or ""}')
    print()
    print('Next: pick candidates to author as skill and/or command.')
    print('  histmgr mine --json …')
    print("  histmgr choose --ids 1,3 --as skill --guidance '…'")
    if sys.stdin.isatty() and not args.no_interactive:
        return interactive_choose(candidates, guidance)
    return 0


def cmd_choose(args: argparse.Namespace) -> int:
    """Non-interactive selection from a prior mine --json file or re-mine."""
    if args.from_json:
        data = json.loads(Path(args.from_json).read_text(encoding='utf-8'))
        candidates = data.get('candidates') or data
        if not isinstance(candidates, list):
            print('Invalid --from-json: expected candidates list', file=sys.stderr)
            return 1
    else:
        root = sessions_root()
        rows = apply_filters(
            load_index(root),
            project=args.project,
            query=args.query,
            since=args.since,
            until=args.until,
            tag=args.tag,
            status=args.status,
            min_transcript_kb=args.min_kb,
            limit=None,
        )
        candidates = mine_candidates(rows)
        annotate_existence(candidates)

    ids: list[int] = []
    for tok in (args.ids or '').split(','):
        tok = tok.strip()
        if tok.isdigit():
            ids.append(int(tok))
        elif tok:
            for i, c in enumerate(candidates, 1):
                if tok in {c.get('id'), c.get('suggested_name')}:
                    ids.append(i)
                    break
    selected: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    for n in ids:
        if 1 <= n <= len(candidates):
            c = dict(candidates[n - 1])
            if args.as_kind:
                c['create_as'] = args.as_kind
            cid = str(c.get('id'))
            if cid not in seen_ids:
                seen_ids.add(cid)
                selected.append(c)
    if not selected:
        print('No matching candidates for --ids', file=sys.stderr)
        return 1
    guidance = args.guidance or ''
    payload = _selection_payload(selected, guidance)
    print(json.dumps(payload, indent=2))
    if args.write:
        Path(args.write).write_text(json.dumps(payload, indent=2), encoding='utf-8')
        print(f'Wrote {args.write}', file=sys.stderr)
    return 0


def remove_from_index(root: Path, session_ids: set[str]) -> int:
    index_path = root / INDEX_NAME
    if not index_path.is_file():
        return 0
    kept: list[str] = []
    removed = 0
    with index_path.open(encoding='utf-8', errors='replace') as fh:
        for line in fh:
            raw = line.strip()
            if not raw:
                continue
            try:
                obj = json.loads(raw)
            except json.JSONDecodeError:
                kept.append(line if line.endswith('\n') else line + '\n')
                continue
            if obj.get('sessionId') in session_ids:
                removed += 1
                continue
            kept.append(json.dumps(obj, ensure_ascii=False) + '\n')
    tmp = index_path.with_suffix('.jsonl.tmp')
    tmp.write_text(''.join(kept), encoding='utf-8')
    tmp.replace(index_path)
    return removed


def _safe_session_dir(root: Path, sid: str) -> Path | None:
    """Resolve sid under root; reject path escape."""
    if not sid or sid in {'.', '..'} or '/' in sid or '\\' in sid:
        return None
    root_res = root.resolve()
    p = (root / sid).resolve()
    try:
        p.relative_to(root_res)
    except ValueError:
        return None
    return p


def cmd_delete(args: argparse.Namespace) -> int:
    root = sessions_root()
    targets: list[str] = list(args.session_ids or [])
    filter_active = any(
        [
            args.filter_query,
            args.query,
            args.project,
            args.since,
            args.until,
            args.tag,
            args.status,
            args.min_kb is not None,
        ]
    )
    if filter_active:
        rows = apply_filters(
            load_index(root),
            project=args.project,
            query=args.filter_query or args.query,
            since=args.since,
            until=args.until,
            tag=args.tag,
            status=args.status,
            min_transcript_kb=args.min_kb,
            limit=args.limit,
        )
        targets.extend(r.session_id for r in rows)
    elif not targets:
        # No ids and no filters: default to ALL sessions (index + on-disk dirs).
        targets.extend(r.session_id for r in load_index(root))
        if root.is_dir():
            targets.extend(
                sorted(p.name for p in root.iterdir() if p.is_dir() and p.name.startswith('session-'))
            )
        print('No filters given: selecting ALL session history.', file=sys.stderr)

    seen: set[str] = set()
    uniq: list[str] = []
    for t in targets:
        if t not in seen:
            seen.add(t)
            uniq.append(t)

    protected = current_session_ids()
    blocked = [s for s in uniq if s in protected]
    if blocked and not args.force_current:
        print(
            'Refusing to delete live/current session(s): ' + ', '.join(blocked),
            file=sys.stderr,
        )
        print('Pass --force-current if you really mean it.', file=sys.stderr)
        uniq = [s for s in uniq if s not in protected]

    if not uniq:
        print('No sessions selected for delete.', file=sys.stderr)
        return 1

    print(f'Will delete {len(uniq)} session(s) under {root}:')
    for sid in uniq:
        p = _safe_session_dir(root, sid)
        print(f'  {sid}  exists_dir={bool(p and p.is_dir())}')

    if args.dry_run:
        print('Dry-run only; nothing deleted.')
        return 0

    if not args.yes:
        if not sys.stdin.isatty():
            print('Refusing delete without --yes in non-interactive mode.', file=sys.stderr)
            return 2
        try:
            conf = input(f'Type DELETE to permanently remove {len(uniq)} sessions: ').strip()
        except EOFError:
            conf = ''
        if conf != 'DELETE':
            print('Aborted.')
            return 3

    errors = 0
    for sid in uniq:
        p = _safe_session_dir(root, sid)
        if p is None:
            print(f'refusing unsafe id: {sid!r}', file=sys.stderr)
            errors += 1
            continue
        try:
            if p.is_dir():
                shutil.rmtree(p)
                print(f'removed dir {p}')
            else:
                print(f'no dir for {sid}')
        except OSError as e:
            print(f'error removing {p}: {e}', file=sys.stderr)
            errors += 1
    remove_from_index(root, set(uniq))
    print('index.jsonl updated')
    return 1 if errors else 0


def cmd_stats(args: argparse.Namespace) -> int:
    root = sessions_root()
    rows = apply_filters(
        load_index(root),
        project=args.project,
        query=args.query,
        since=args.since,
        until=args.until,
        tag=args.tag,
        status=args.status,
        min_transcript_kb=args.min_kb,
        limit=None,
    )
    by_proj = Counter((r.project_dir or '(none)') for r in rows)
    with_t = sum(1 for r in rows if r.transcript_size > 0)
    print(f'total={len(rows)} with_transcript={with_t} root={root}')
    print('top projects:')
    for p, n in by_proj.most_common(args.limit or 15):
        print(f'  {n:4d}  {p}')
    tag_c: Counter[str] = Counter()
    for r in rows:
        for t in detect_tags(r):
            tag_c[t] += 1
    print('pattern tags:')
    for t, n in tag_c.most_common():
        print(f'  {n:4d}  {t}')
    if args.json:
        json.dump(
            {
                'total': len(rows),
                'with_transcript': with_t,
                'projects': by_proj.most_common(),
                'tags': tag_c.most_common(),
            },
            sys.stdout,
            indent=2,
        )
        print()
    return 0


def cmd_patterns(_args: argparse.Namespace) -> int:
    """List built-in mining pattern rules."""
    for pid, kind, name, cre in PATTERN_RULES:
        print(f'{pid:20} {kind:8} {name:40} {cre.pattern}')
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog='histmgr',
        description='Junie session history manager and reusable-workflow miner',
    )
    p.add_argument('--junie-home', help='Override JUNIE_HOME')
    p.add_argument(
        '--check-args',
        action='store_true',
        help='Parse argv, print the resolved namespace as JSON and exit 0 (no session access)',
    )
    sub = p.add_subparsers(dest='cmd', required=True)

    def add_filters(sp: argparse.ArgumentParser) -> None:
        sp.add_argument('--project', '-p', help='Substring match on projectDir')
        sp.add_argument('--query', '-q', help='Regex on taskName/transcript head')
        sp.add_argument('--since', help='YYYY-MM-DD inclusive lower bound on updatedAt')
        sp.add_argument('--until', help='YYYY-MM-DD inclusive upper bound on updatedAt')
        sp.add_argument('--tag', help='Pattern tag id (e.g. kamailio, todo_implement)')
        sp.add_argument('--status', help='Exact session status match (e.g. finished)')
        sp.add_argument('--min-kb', type=int, default=None, help='Min transcript size KiB')
        sp.add_argument('--limit', '-n', type=int, default=None)

    sp = sub.add_parser('list', help='List/filter sessions')
    add_filters(sp)
    sp.add_argument('--json', action='store_true')
    sp.set_defaults(func=cmd_list)

    sp = sub.add_parser('show', help='Show one session metadata / transcript')
    sp.add_argument('session_id')
    sp.add_argument('--transcript', '-t', action='store_true')
    sp.add_argument('--max-chars', type=int, default=20000)
    sp.set_defaults(func=cmd_show)

    sp = sub.add_parser('mine', help='Mine reusable skill/command candidates')
    add_filters(sp)
    sp.add_argument('--json', action='store_true')
    sp.add_argument('--guidance', '-g', default='', help='Extra guidance for later authors')
    sp.add_argument('--no-interactive', action='store_true')
    sp.add_argument('--exclude-existing', action='store_true', help='Hide patterns that already have a skill/command')
    sp.add_argument('--min-hits', type=int, default=1, help='Minimum session hits to list a pattern')
    sp.set_defaults(func=cmd_mine)

    sp = sub.add_parser('choose', help='Select mine candidates as skill or command')
    add_filters(sp)
    sp.add_argument('--from-json', help='Prior mine --json output file')
    sp.add_argument('--ids', required=True, help='Comma ids/names from mine list')
    sp.add_argument('--as', dest='as_kind', choices=['skill', 'command'], help='Force artifact type')
    sp.add_argument('--guidance', '-g', default='')
    sp.add_argument('--write', help='Write selection JSON path')
    sp.set_defaults(func=cmd_choose)

    sp = sub.add_parser('delete', help='Delete session dirs + index rows')
    add_filters(sp)
    sp.add_argument('session_ids', nargs='*', help='Explicit session ids')
    sp.add_argument('--filter-query', help='Alias of --query for delete filters')
    sp.add_argument('--yes', '-y', action='store_true', help='Skip interactive confirm')
    sp.add_argument('--dry-run', action='store_true')
    sp.add_argument(
        '--force-current',
        action='store_true',
        help='Allow deleting the detected live/current session',
    )
    sp.set_defaults(func=cmd_delete)

    sp = sub.add_parser('stats', help='Histogram of projects and pattern tags')
    add_filters(sp)
    sp.add_argument('--json', action='store_true')
    sp.set_defaults(func=cmd_stats)

    sp = sub.add_parser('patterns', help='List built-in mine pattern rules')
    sp.set_defaults(func=cmd_patterns)

    return p


def _normalize_argv(argv: list[str] | None) -> list[str]:
    """Default bare invocation to ``mine --limit 20 --no-interactive``."""
    if argv is None:
        argv_list = list(sys.argv[1:])
    else:
        argv_list = list(argv)
    globals_with_val = {'--junie-home'}
    globals_bool = {'-h', '--help'}
    i = 0
    saw_cmd = False
    while i < len(argv_list):
        tok = argv_list[i]
        if tok in globals_bool:
            return argv_list
        if tok == '--check-args':
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
        argv_list.extend(['mine', '--limit', '20', '--no-interactive'])
    return argv_list


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(_normalize_argv(argv))
    if args.check_args:
        print(json.dumps({k: v for k, v in vars(args).items() if k != 'func'}, default=str))
        return 0
    if args.junie_home:
        os.environ['JUNIE_HOME'] = args.junie_home
    return int(args.func(args) or 0)


if __name__ == '__main__':
    sys.exit(main())
