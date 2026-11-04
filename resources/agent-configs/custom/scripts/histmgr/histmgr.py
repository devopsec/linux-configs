#!/usr/bin/env python3
"""
histmgr — coding-agent session history manager / skill-miner helper.

Catalog, filter, mine reusable workflows from agent session history, and
optionally delete sessions. Supports Junie CLI (~/.junie/sessions) and Claude
Code (~/.claude/projects/*/<session>.jsonl); pick one with --agent, AGENT_TARGET,
or the interactive prompt when run standalone in a terminal. Designed for agent
+ human use (arg-based; interactive prompts when stdin is a TTY and flags omit
choices).
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

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from agent_target import AGENT_NAMES, AgentSelectionError, agent_home, resolve_agent  # noqa: E402

DEFAULT_JUNIE_HOME = Path(os.environ.get('JUNIE_HOME', Path.home() / '.junie'))
SESSIONS_DIRNAME = 'sessions'
INDEX_NAME = 'index.jsonl'
CLAUDE_PROJECTS_DIRNAME = 'projects'
# Claude Code keeps per-session state under these home subdirectories, keyed by session id.
CLAUDE_SESSION_SIDECARS = ('file-history', 'session-env')
_SESSION_ID_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]*$')

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
     re.compile(r'create a skill|agent skill|~/\.(junie|claude)/skills|update.*skill', re.I)),
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
    agent: str = 'junie'

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


# ── Claude Code sessions (~/.claude/projects/<encoded-cwd>/<session-id>.jsonl) ──


def _iso_ms(value: Any) -> int | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return int(datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp() * 1000)
    except ValueError:
        return None


def _claude_text(content: Any) -> str:
    """Plain text of a message: strings and text blocks; tool calls/results and thinking skipped."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = [b.get('text', '') for b in content if isinstance(b, dict) and b.get('type') == 'text']
        return '\n'.join(p for p in parts if p)
    return ''


def claude_transcript(path: Path | None, limit: int | None = 8000) -> str:
    """User/assistant text of a Claude session file as markdown-ish text, up to ``limit`` chars."""
    if not path or not path.is_file():
        return ''
    out: list[str] = []
    size = 0
    try:
        with path.open(encoding='utf-8', errors='replace') as fh:
            for line in fh:
                # cheap prefilter before parsing; the parsed record is checked below
                if '"user"' not in line and '"assistant"' not in line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if obj.get('type') not in ('user', 'assistant') or obj.get('isMeta') or obj.get('isSidechain'):
                    continue
                text = _claude_text((obj.get('message') or {}).get('content')).strip()
                if not text:
                    continue
                chunk = f'## {obj.get("type")}\n{text}\n\n'
                out.append(chunk)
                size += len(chunk)
                if limit is not None and size >= limit:
                    break
    except OSError:
        return ''
    text = ''.join(out)
    return text[:limit] if limit is not None else text


def load_claude_session(path: Path) -> SessionRow:
    """Metadata of one Claude session file without parsing every record."""
    created: int | None = None
    cwd: str | None = None
    title: str | None = None
    first_prompt: str | None = None
    try:
        with path.open(encoding='utf-8', errors='replace') as fh:
            for line in fh:
                if '"ai-title"' in line:
                    try:
                        title = json.loads(line).get('aiTitle') or title
                    except json.JSONDecodeError:
                        pass
                    continue
                if (created is None or cwd is None or first_prompt is None) and '"timestamp"' in line:
                    try:
                        obj = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    created = created or _iso_ms(obj.get('timestamp'))
                    cwd = cwd or obj.get('cwd')
                    if first_prompt is None and obj.get('type') == 'user' and not obj.get('isMeta'):
                        text = _claude_text((obj.get('message') or {}).get('content')).strip()
                        if text and not text.startswith('<'):
                            first_prompt = text.splitlines()[0][:120]
        st = path.stat()
        updated = int(st.st_mtime * 1000)
        size = st.st_size
    except OSError:
        updated, size = None, 0
    return SessionRow(
        session_id=path.stem,
        task_name=title or first_prompt,
        project_dir=cwd,
        status=None,
        created_at=created,
        updated_at=updated,
        transcript_size=size,
        path=path,
        agent='claude',
    )


def row_text(row: SessionRow, limit: int = 8000) -> str:
    """Transcript head for filtering/mining, whatever agent the row came from."""
    if row.agent == 'claude':
        return claude_transcript(row.path, limit)
    return read_transcript_head(row.path, limit)


def _pid_alive(pid: Any) -> bool:
    try:
        os.kill(int(pid), 0)
    except (OSError, ValueError, TypeError):
        return False
    return True


class JunieBackend:
    """Junie CLI: sessions/<id>/transcript.md plus sessions/index.jsonl."""

    name = 'junie'

    def __init__(self, home: Path) -> None:
        self.home = home

    @property
    def root(self) -> Path:
        return self.home / SESSIONS_DIRNAME

    def load_rows(self) -> list[SessionRow]:
        return load_index(self.root)

    def find(self, sid: str) -> tuple[SessionRow, dict[str, Any]] | None:
        path = _safe_session_dir(self.root, sid)
        if path is None or not path.is_dir():
            return None
        meta: dict[str, Any] = {'sessionId': sid}
        index = self.root / INDEX_NAME
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
        return row, meta

    def transcript(self, row: SessionRow) -> tuple[Path | None, str | None]:
        t = row.path / 'transcript.md' if row.path else None
        if t is None or not t.is_file():
            return t, None
        return t, t.read_text(encoding='utf-8', errors='replace')

    def current_ids(self) -> set[str]:
        return current_session_ids()

    def all_ids(self) -> list[str]:
        ids = [r.session_id for r in self.load_rows()]
        if self.root.is_dir():
            ids.extend(sorted(p.name for p in self.root.iterdir() if p.is_dir() and p.name.startswith('session-')))
        return ids

    def paths_for(self, sid: str) -> list[Path]:
        p = _safe_session_dir(self.root, sid)
        return [p] if p is not None and p.exists() else []

    def finish_delete(self, ids: set[str]) -> None:
        remove_from_index(self.root, ids)
        print('index.jsonl updated')


class ClaudeBackend:
    """Claude Code: projects/<encoded-cwd>/<id>.jsonl (+ <id>/ sidecar, file-history/<id>, session-env/<id>)."""

    name = 'claude'

    def __init__(self, home: Path) -> None:
        self.home = home

    @property
    def root(self) -> Path:
        return self.home / CLAUDE_PROJECTS_DIRNAME

    def _files(self) -> list[Path]:
        if not self.root.is_dir():
            return []
        return sorted(f for d in self.root.iterdir() if d.is_dir() for f in d.glob('*.jsonl'))

    def load_rows(self) -> list[SessionRow]:
        rows = [load_claude_session(f) for f in self._files()]
        rows.sort(key=lambda r: r.sort_ts, reverse=True)
        return rows

    def _file_for(self, sid: str) -> Path | None:
        if not _SESSION_ID_RE.match(sid or ''):
            return None
        matches = [f for f in self._files() if f.stem == sid]
        return matches[0] if matches else None

    def find(self, sid: str) -> tuple[SessionRow, dict[str, Any]] | None:
        f = self._file_for(sid)
        if f is None:
            return None
        row = load_claude_session(f)
        meta = {
            'sessionId': sid,
            'taskName': row.task_name,
            'projectDir': row.project_dir,
            'createdAt': row.created_at,
            'updatedAt': row.updated_at,
            'file': str(f),
        }
        return row, meta

    def transcript(self, row: SessionRow) -> tuple[Path | None, str | None]:
        if not row.path or not row.path.is_file():
            return row.path, None
        return row.path, claude_transcript(row.path, None)

    def current_ids(self) -> set[str]:
        found: set[str] = set()
        live = os.environ.get('CLAUDE_CODE_SESSION_ID')
        if live:
            found.add(live)
        # Running Claude Code processes register themselves in ~/.claude/sessions/<pid>.json.
        reg = self.home / 'sessions'
        if reg.is_dir():
            for f in reg.glob('*.json'):
                try:
                    obj = json.loads(f.read_text(encoding='utf-8'))
                except (OSError, json.JSONDecodeError):
                    continue
                if obj.get('sessionId') and _pid_alive(obj.get('pid')):
                    found.add(str(obj['sessionId']))
        return found

    def all_ids(self) -> list[str]:
        return [f.stem for f in self._files()]

    def paths_for(self, sid: str) -> list[Path]:
        f = self._file_for(sid)
        if f is None:
            return []
        out = [f]
        sidecar = f.parent / sid  # subagents/, tool-results/ — never the project's memory/
        if sidecar.is_dir() and sidecar.name == sid:
            out.append(sidecar)
        for sub in CLAUDE_SESSION_SIDECARS:
            extra = self.home / sub / sid
            if extra.exists():
                out.append(extra)
        return out

    def finish_delete(self, ids: set[str]) -> None:
        return None


def make_backend(agent: str, home: str | Path | None = None) -> JunieBackend | ClaudeBackend:
    resolved = agent_home(agent, home)
    return ClaudeBackend(resolved) if agent == 'claude' else JunieBackend(resolved)


def _backend(args: argparse.Namespace) -> JunieBackend | ClaudeBackend:
    """Backend for this invocation (resolved once in main, or here for direct cmd_* calls)."""
    be = getattr(args, 'backend', None)
    if be is None:
        agent = resolve_agent(getattr(args, 'agent', None), interactive=False)
        be = make_backend(agent, getattr(args, 'home', None))
        args.backend = be
    return be


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
            head = row_text(r, 4000)
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
    blob = f'{row.task_name or ""}\n{row_text(row, 6000)}'
    tags = [pid for pid, _kind, _name, cre in PATTERN_RULES if cre.search(blob)]
    return tags or ['other']


def existing_artifacts(home: Path | None = None) -> tuple[set[str], set[str]]:
    home = home or junie_home()
    skills: set[str] = set()
    commands: set[str] = set()
    skills_dir = home / 'skills'
    if skills_dir.is_dir():
        skills = {p.name for p in skills_dir.iterdir() if p.is_dir()}
    commands_dir = home / 'commands'
    if commands_dir.is_dir():
        commands = {p.stem for p in commands_dir.glob('*.md')}
    return skills, commands


def annotate_existence(candidates: list[dict[str, Any]], home: Path | None = None) -> None:
    skills, commands = existing_artifacts(home)
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
    be = _backend(args)
    root = be.root
    rows = apply_filters(
        be.load_rows(),
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
                'agent': r.agent,
            }
            for r in rows
        ]
        json.dump(payload, sys.stdout, indent=2)
        print()
        return 0

    print(f'agent={be.name}  sessions_root={root}  count={len(rows)}')
    print(f'{"WHEN":<16} {"KB":>5}  {"SESSION_ID":<32}  PROJECT  TASK')
    for r in rows:
        proj = (r.project_dir or '').replace(str(Path.home()), '~')
        if len(proj) > 40:
            proj = '…' + proj[-39:]
        task = (r.task_name or '(untitled)')[:50]
        print(f'{r.when():<16} {r.transcript_size // 1024:>5}  {r.session_id:<32}  {proj}  {task}')
    return 0


def cmd_show(args: argparse.Namespace) -> int:
    be = _backend(args)
    sid = args.session_id
    found = be.find(sid)
    if found is None:
        print(f'Session not found: {sid} (agent={be.name}, root={be.root})', file=sys.stderr)
        return 1
    row, meta = found
    meta['agent'] = be.name
    meta['tags'] = detect_tags(row)
    meta['when'] = row.when()
    print(json.dumps(meta, indent=2))
    t, text = be.transcript(row)
    if args.transcript and text is not None:
        if args.max_chars and len(text) > args.max_chars:
            print(text[: args.max_chars])
            print(f'\n… truncated at {args.max_chars} chars')
        else:
            print(text)
    else:
        size = t.stat().st_size if t is not None and t.is_file() else 0
        print(f'transcript: {t if t is not None and t.is_file() else "missing"} size={size}')
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
        blob = f'{r.task_name or ""}\n{row_text(r, 6000)}'
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


def _selection_payload(selected: list[dict[str, Any]], guidance: str, agent: str = 'junie') -> dict[str, Any]:
    return {
        'selected': selected,
        'guidance': guidance,
        'agent': agent,
        'instruction': (
            'Create or update the selected agent skills/commands using '
            f'dev-agents-skill-create for skills and ~/.{agent}/commands/<name>.md for commands '
            '(in the linux-configs repo: resources/agent-configs/commands/, synced to every agent). '
            'Honor optional guidance. Do not overwrite without explicit approval.'
        ),
    }


def interactive_choose(candidates: list[dict[str, Any]], guidance: str, agent: str = 'junie') -> int:
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
    payload = _selection_payload(selected, g, agent)
    out = Path('/tmp') / f'histmgr-selection-{os.getpid()}.json'
    out.write_text(json.dumps(payload, indent=2), encoding='utf-8')
    print(json.dumps(payload, indent=2))
    print(f'Wrote {out}')
    return 0


def cmd_mine(args: argparse.Namespace) -> int:
    be = _backend(args)
    root = be.root
    rows = apply_filters(
        be.load_rows(),
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
    annotate_existence(candidates, be.home)
    if args.min_hits and args.min_hits > 1:
        candidates = [c for c in candidates if c['count'] >= args.min_hits]
    if args.exclude_existing:
        candidates = [c for c in candidates if not c.get('already_exists')]
    if args.limit:
        candidates = candidates[: args.limit]

    guidance = args.guidance or ''

    if args.json:
        json.dump(
            {'agent': be.name, 'candidates': candidates, 'guidance': guidance, 'session_count': len(rows)},
            sys.stdout,
            indent=2,
        )
        print()
        return 0

    print(f'Mined {len(candidates)} candidate patterns from {len(rows)} {be.name} sessions ({root})')
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
        return interactive_choose(candidates, guidance, be.name)
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
        be = _backend(args)
        rows = apply_filters(
            be.load_rows(),
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
        annotate_existence(candidates, be.home)

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
    agent = data.get('agent', 'junie') if args.from_json and isinstance(data, dict) else _backend(args).name
    payload = _selection_payload(selected, guidance, agent)
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
    be = _backend(args)
    root = be.root
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
            be.load_rows(),
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
        # No ids and no filters: default to ALL sessions of the selected agent.
        targets.extend(be.all_ids())
        print(f'No filters given: selecting ALL {be.name} session history.', file=sys.stderr)

    seen: set[str] = set()
    uniq: list[str] = []
    for t in targets:
        if t not in seen:
            seen.add(t)
            uniq.append(t)

    protected = be.current_ids()
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

    print(f'Will delete {len(uniq)} {be.name} session(s) under {root}:')
    for sid in uniq:
        paths = be.paths_for(sid)
        print(f'  {sid}  exists={bool(paths)}')
        for path in paths:
            print(f'      {path}')

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
        if not _SESSION_ID_RE.match(sid):
            print(f'refusing unsafe id: {sid!r}', file=sys.stderr)
            errors += 1
            continue
        paths = be.paths_for(sid)
        if not paths:
            print(f'nothing on disk for {sid}')
            continue
        for p in paths:
            try:
                if p.is_dir() and not p.is_symlink():
                    shutil.rmtree(p)
                    print(f'removed dir {p}')
                else:
                    p.unlink()
                    print(f'removed file {p}')
            except OSError as e:
                print(f'error removing {p}: {e}', file=sys.stderr)
                errors += 1
    be.finish_delete(set(uniq))
    return 1 if errors else 0


def cmd_stats(args: argparse.Namespace) -> int:
    be = _backend(args)
    root = be.root
    rows = apply_filters(
        be.load_rows(),
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
    print(f'agent={be.name} total={len(rows)} with_transcript={with_t} root={root}')
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
                'agent': be.name,
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
        description='Coding-agent session history manager and reusable-workflow miner (Junie CLI, Claude Code)',
        epilog=(
            'Target agent: --agent, else AGENT_TARGET, else the calling agent, else the only installed one, '
            'else an interactive prompt (terminal) — non-interactive runs without a resolvable agent exit 2.'
        ),
    )
    p.add_argument('--agent', choices=AGENT_NAMES, help='Agent whose history to use (default: auto, see below)')
    p.add_argument('--home', help="Override the selected agent's home (default: JUNIE_HOME/CLAUDE_HOME or ~/.junie, ~/.claude)")
    p.add_argument('--junie-home', help='Override JUNIE_HOME (implies --agent junie)')
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
    globals_with_val = {'--junie-home', '--agent', '--home'}
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
        if any(tok.startswith(f'{g}=') for g in globals_with_val):
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
        if not args.agent:
            args.agent = 'junie'
    try:
        agent = resolve_agent(args.agent, purpose=f'histmgr {args.cmd}')
    except AgentSelectionError as exc:
        print(f'histmgr: {exc}', file=sys.stderr)
        return 2
    if agent == 'junie' and args.home:
        os.environ['JUNIE_HOME'] = args.home
    args.backend = make_backend(agent, args.home)
    return int(args.func(args) or 0)


if __name__ == '__main__':
    sys.exit(main())
