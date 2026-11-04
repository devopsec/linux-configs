"""Discover skills, commands, docs, MCP, models."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .paths import AgentPaths, JuniePaths, make_paths

FRONTMATTER_RE = re.compile(r'^---\s*\n(.*?)\n---\s*\n?', re.DOTALL)
NAME_RE = re.compile(r'^name:\s*["\']?([^"\'\n]+)["\']?\s*$', re.M)
DESC_RE = re.compile(r'^description:\s*["\']?(.*?)["\']?\s*$', re.M | re.S)
# YAML description may be quoted multi-line-ish; keep simple single-line + folded
DESC_BLOCK_RE = re.compile(
    r'^description:\s*(?:>-?\s*)?(?:["\'](.+?)["\']|(.+))$',
    re.M | re.S,
)


@dataclass
class SkillInfo:
    name: str
    path: Path
    description: str = ''
    has_skill_md: bool = False
    has_agents_junie: bool = False
    has_agents_claude: bool = False
    has_references: bool = False
    has_scripts: bool = False
    triggers_hint: str = ''


@dataclass
class CommandInfo:
    name: str
    path: Path
    description: str = ''
    allow_prompt_argument: bool = False
    required_placeholders: list[str] = field(default_factory=list)
    script: str | None = None
    examples: list[str] = field(default_factory=list)

    @property
    def arg_mode(self) -> str:
        """Human label for how Junie will treat invocation args."""
        if self.required_placeholders:
            names = ', '.join(self.required_placeholders)
            base = f'required: {names}'
            if self.allow_prompt_argument:
                return f'{base} + optional free-form'
            return base
        if self.allow_prompt_argument:
            return 'optional free-form (allowPromptArgument)'
        return 'no args'


_PLACEHOLDER_RE = re.compile(r'\$([A-Za-z_][A-Za-z0-9_]*)')
_EXAMPLES_RE = re.compile(r'^```text[ \t]*\n(.*?)^```', re.M | re.S)
_SCRIPT_RE = re.compile(r'^\s*python3\s+(~/\.(?:junie|claude)/custom/scripts/\S+\.py)\b', re.M)


def extract_command_examples(body: str) -> list[str]:
    """Example argv lines from the first ```text block of a command body (blank lines dropped)."""
    m = _EXAMPLES_RE.search(body or '')
    if not m:
        return []
    return [ln.strip() for ln in m.group(1).splitlines() if ln.strip()]


def extract_command_script(body: str) -> str | None:
    """Tilde path of the wrapped `python3 ~/.<agent>/custom/scripts/...py` script, if any."""
    m = _SCRIPT_RE.search(body or '')
    return m.group(1) if m else None


# Junie optional free-form slot when allowPromptArgument: true (not a required name=value arg).
_OPTIONAL_PROMPT_NAMES = frozenset({'prompt'})


def extract_command_placeholders(body: str) -> list[str]:
    """Return unique dollar-sign template arg names in a command body (order preserved)."""
    seen: set[str] = set()
    out: list[str] = []
    for m in _PLACEHOLDER_RE.finditer(body or ''):
        name = m.group(1)
        if name not in seen:
            seen.add(name)
            out.append(name)
    return out


def required_command_placeholders(body: str, allow_prompt_argument: bool = False, agent: str = 'junie') -> list[str]:
    """Placeholders that block bare /cmd until name=value is supplied.

    Junie: when allowPromptArgument is true, ``$prompt`` is the optional free-form slot and
    must not be treated as a required named arg (bare /cmd must still run); any other
    dollar placeholder is a required named arg. Claude Code only substitutes ``$ARGUMENTS``
    and ``$1``…``$9`` (both optional) and leaves other dollar text alone, so nothing blocks.
    """
    if agent == 'claude':
        return []
    names = extract_command_placeholders(body)
    if allow_prompt_argument:
        return [n for n in names if n.lower() not in _OPTIONAL_PROMPT_NAMES]
    return names


@dataclass
class ModelInfo:
    file_stem: str
    path: Path
    data: dict[str, Any] = field(default_factory=dict)


def _parse_frontmatter(text: str) -> dict[str, str]:
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}
    out: dict[str, str] = {}
    lines = m.group(1).splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        i += 1
        km = _TOP_KEY_RE.match(line)
        if not km:
            continue
        key, val = km.group(1), (km.group(2) or '').strip()
        # gather continuation lines (indented or blank) belonging to this key
        cont: list[str] = []
        while i < len(lines) and (not lines[i].strip() or lines[i][:1] in (' ', '\t')):
            cont.append(lines[i])
            i += 1
        while cont and not cont[-1].strip():
            cont.pop()
        if key not in out:
            out[key] = _yaml_scalar(val, cont)
    return out


_TOP_KEY_RE = re.compile(r'^([A-Za-z_][\w-]*)\s*:(?:\s+(.*)|\s*)$')


def _yaml_scalar(first: str, cont: list[str]) -> str:
    """Resolve a YAML scalar: block (|, >), quoted multi-line, or plain multi-line."""
    first = first or ''
    if first[:1] in ('|', '>'):
        body = [c.strip() for c in cont]
        if first[0] == '|':
            return '\n'.join(body).strip()
        paras, cur = [], []
        for b in body:
            if b:
                cur.append(b)
            elif cur:
                paras.append(' '.join(cur))
                cur = []
        if cur:
            paras.append(' '.join(cur))
        return '\n'.join(paras).strip()
    joined = ' '.join([first, *(c.strip() for c in cont if c.strip())]).strip()
    if len(joined) >= 2 and joined[0] == joined[-1] and joined[0] in ('"', "'"):
        inner = joined[1:-1]
        return inner.replace("''", "'") if joined[0] == "'" else inner.replace('\\"', '"')
    if joined.startswith('[') or joined.startswith('{'):
        return joined
    return joined.strip('"').strip("'")


def list_skills(paths: JuniePaths | None = None, query: str | None = None) -> list[SkillInfo]:
    p = paths or make_paths()
    root = p.skills
    if not root.is_dir():
        return []
    skills: list[SkillInfo] = []
    for d in sorted(root.iterdir()):
        if not d.is_dir() or d.name.startswith('.'):
            continue
        skill_md = d / 'SKILL.md'
        meta: dict[str, str] = {}
        desc = ''
        name = d.name
        has_md = skill_md.is_file()
        if has_md:
            text = skill_md.read_text(encoding='utf-8', errors='replace')
            meta = _parse_frontmatter(text)
            name = meta.get('name', d.name)
            desc = meta.get('description', '')
            # triggers section hint
            tm = re.search(r'(?i)^(?:##\s*)?triggers?:?\s*$', text, re.M)
            triggers = ''
            if tm:
                # take next non-empty lines until blank/heading
                lines = []
                for line in text[tm.end():].splitlines():
                    if not line.strip():
                        if lines:
                            break
                        continue
                    if line.startswith('#'):
                        break
                    lines.append(line.strip(' -'))
                    if len(lines) >= 3:
                        break
                triggers = '; '.join(lines)
            else:
                # description often embeds "Use when…"
                if 'use when' in desc.lower():
                    triggers = desc
        info = SkillInfo(
            name=name,
            path=d,
            description=desc,
            has_skill_md=has_md,
            has_agents_junie=(d / 'agents' / 'junie.md').is_file(),
            has_agents_claude=(d / 'agents' / 'claude.md').is_file(),
            has_references=(d / 'references').is_dir(),
            has_scripts=(d / 'scripts').is_dir(),
            triggers_hint=triggers if has_md else '',
        )
        if query:
            q = query.lower()
            blob = f'{info.name} {info.description} {info.path.name}'.lower()
            if q not in blob:
                continue
        skills.append(info)
    return skills


def list_commands(paths: JuniePaths | None = None, query: str | None = None) -> list[CommandInfo]:
    p = paths or make_paths()
    root = p.commands
    if not root.is_dir():
        return []
    cmds: list[CommandInfo] = []
    for f in sorted(root.glob('*.md')):
        if f.name.startswith('.'):
            continue
        text = f.read_text(encoding='utf-8', errors='replace')
        meta = _parse_frontmatter(text)
        name = f.stem
        desc = meta.get('description', '')
        body = text
        fm = FRONTMATTER_RE.match(text)
        if fm:
            body = text[fm.end() :]
        allow_raw = meta.get('allowPromptArgument', meta.get('allow_prompt_argument', '')).strip().lower()
        allow = allow_raw in ('true', 'yes', '1')
        placeholders = required_command_placeholders(body, allow_prompt_argument=allow, agent=p.agent)
        info = CommandInfo(
            name=name,
            path=f,
            description=desc,
            allow_prompt_argument=allow,
            required_placeholders=placeholders,
            script=extract_command_script(body),
            examples=extract_command_examples(body),
        )
        if query:
            q = query.lower()
            if q not in f'{name} {desc} {info.arg_mode}'.lower():
                continue
        cmds.append(info)
    return cmds


def list_guideline_docs(paths: JuniePaths | None = None) -> list[Path]:
    p = paths or make_paths()
    docs: list[Path] = []
    if p.agents_md.is_file():
        docs.append(p.agents_md)
    if p.custom_docs.is_dir():
        for f in sorted(p.custom_docs.rglob('*.md')):
            docs.append(f)
    return docs


def list_models(paths: JuniePaths | None = None) -> list[ModelInfo]:
    p = paths or make_paths()
    if not p.models.is_dir():
        return []
    out: list[ModelInfo] = []
    for f in sorted(p.models.glob('*.json')):
        data: dict[str, Any] = {}
        try:
            data = json.loads(f.read_text(encoding='utf-8'))
        except json.JSONDecodeError:
            data = {'_error': 'invalid json'}
        out.append(ModelInfo(file_stem=f.stem, path=f, data=data))
    return out


_REDACTED = '<redacted>'


def _redact_server(cfg: Any) -> Any:
    """Keep names/commands/args; hide env and header values (they may hold tokens)."""
    if not isinstance(cfg, dict):
        return cfg
    out = dict(cfg)
    for key in ('env', 'headers'):
        if isinstance(out.get(key), dict):
            out[key] = {k: _REDACTED for k in out[key]}
    return out


def load_mcp(paths: JuniePaths | None = None) -> dict[str, Any]:
    """MCP config as ``{'mcpServers': {...}}``. For Claude Code only the user-scope servers of
    ~/.claude.json are returned (the rest of that file is account/project state), redacted."""
    p = paths or make_paths()
    if not p.mcp.is_file():
        return {}
    try:
        data = json.loads(p.mcp.read_text(encoding='utf-8'))
    except json.JSONDecodeError:
        return {'_error': f'invalid {p.mcp.name}'}
    if p.agent == 'claude':
        servers = data.get('mcpServers') or {}
        return {'mcpServers': {name: _redact_server(cfg) for name, cfg in servers.items()}}
    return data


def session_count(paths: JuniePaths | None = None) -> int:
    p = paths or make_paths()
    if not p.sessions.is_dir():
        return 0
    if p.agent == 'claude':
        return sum(1 for d in p.sessions.iterdir() if d.is_dir() for _ in d.glob('*.jsonl'))
    return sum(1 for d in p.sessions.iterdir() if d.is_dir() and d.name.startswith('session-'))


def status_snapshot(paths: JuniePaths | None = None) -> dict[str, Any]:
    p = paths or make_paths()
    skills = list_skills(p)
    cmds = list_commands(p)
    models = list_models(p)
    mcp = load_mcp(p)
    servers = mcp.get('mcpServers') or {}
    enabled = sum(
        1
        for v in servers.values()
        if isinstance(v, dict) and v.get('enabled', True) is not False
    )
    cfg: dict[str, Any] = {}
    settings: dict[str, Any] = {}
    if p.config.is_file():
        try:
            cfg = json.loads(p.config.read_text(encoding='utf-8'))
        except json.JSONDecodeError:
            cfg = {'_error': 'invalid'}
    if p.settings.is_file():
        try:
            settings = json.loads(p.settings.read_text(encoding='utf-8'))
        except json.JSONDecodeError:
            settings = {'_error': 'invalid'}
    missing_doc = sum(
        1 for s in skills if not (s.has_agents_claude if p.agent == 'claude' else s.has_agents_junie)
    )
    return {
        'agent': p.agent,
        'label': p.label,
        'home': str(p.home),
        'entrypoint': str(p.agents_md),
        'skills': len(skills),
        'skills_with_skill_md': sum(1 for s in skills if s.has_skill_md),
        'skills_missing_agent_doc': missing_doc,
        'skills_missing_junie_agent': sum(1 for s in skills if not s.has_agents_junie),
        'commands': len(cmds),
        'models': len(models),
        'mcp_servers': len(servers),
        'mcp_enabled': enabled,
        'sessions': session_count(p),
        'config': cfg,
        'settings_keys': sorted(settings.keys()),
        'provider': settings.get('provider') or cfg.get('provider'),
        'model': settings.get('model'),
        'modelForLaunch': settings.get('modelForLaunch'),
        'braveMode': settings.get('braveMode'),
        'token_budget': cfg.get('token-budget'),
        'time_limit': cfg.get('time-limit'),
        'brave_flag': cfg.get('brave'),
        'theme': settings.get('theme'),
        'permissions_mode': (settings.get('permissions') or {}).get('defaultMode')
        if isinstance(settings.get('permissions'), dict) else None,
    }
