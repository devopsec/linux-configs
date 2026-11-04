"""Pretty rendering of agent documentation (global + project)."""

from __future__ import annotations

from pathlib import Path
from typing import Literal

from .inventory import CommandInfo, SkillInfo, list_commands, list_guideline_docs, list_skills
from .paths import JuniePaths, find_project_agents_roots, make_paths
from .pretty import Style, header, hr, kv, markdown_outline, markdown_toc, table

FormatName = Literal['pretty', 'toc', 'outline', 'raw', 'tree', 'cards']


def _read(path: Path, max_chars: int | None = None) -> str:
    text = path.read_text(encoding='utf-8', errors='replace')
    if max_chars is not None and len(text) > max_chars:
        return text[: max_chars - 1] + '…'
    return text


def resolve_doc_target(
    name: str,
    paths: JuniePaths | None = None,
    project_root: Path | None = None,
) -> Path | None:
    """Map short names to documentation files."""
    p = paths or make_paths()
    key = name.strip().lower().lstrip('/')
    aliases = {
        'agents': p.agents_md,
        'agents.md': p.agents_md,
        'guidelines': p.general_guidelines,
        'general': p.general_guidelines,
        'general-guidelines': p.general_guidelines,
        'skills-catalog': p.skills_catalog,
        'skills': p.skills_catalog,
        'commands-catalog': p.commands_catalog,
        'commands': p.commands_catalog,
        'sadkitti': p.sadkitti / 'spec.md',
        'sadkitti-spec': p.sadkitti / 'spec.md',
        'sadkitti-usage': p.sadkitti / 'usage.md',
        'python': p.custom_docs / 'python-guidelines.md',
        'bash': p.custom_docs / 'bash-guidelines.md',
        'security': p.custom_docs / 'security-guidelines.md',
        'testing': p.custom_docs / 'testing-guidelines.md',
        'infra': p.custom_docs / 'infrastructure-guidelines.md',
        'infrastructure': p.custom_docs / 'infrastructure-guidelines.md',
    }
    if key in aliases:
        path = aliases[key]
        return path if path.is_file() else None

    # skill:<name> or command:<name>
    if key.startswith('skill:'):
        sk = key.split(':', 1)[1]
        cand = p.skills / sk / 'SKILL.md'
        return cand if cand.is_file() else None
    if key.startswith('command:') or key.startswith('cmd:'):
        ck = key.split(':', 1)[1]
        cand = p.commands / f'{ck}.md'
        return cand if cand.is_file() else None

    # bare skill/command name
    skill_md = p.skills / name / 'SKILL.md'
    if skill_md.is_file():
        return skill_md
    cmd_md = p.commands / f'{name}.md'
    if cmd_md.is_file():
        return cmd_md

    # path-like
    direct = Path(name).expanduser()
    if direct.is_file():
        return direct.resolve()

    # relative under custom/docs
    under = p.custom_docs / name
    if under.is_file():
        return under
    if not name.endswith('.md'):
        under2 = p.custom_docs / f'{name}.md'
        if under2.is_file():
            return under2

    # project AGENTS
    if key in ('project', 'project-agents', 'project/agents'):
        roots = find_project_agents_roots(project_root)
        return roots[0] if roots else None

    return None


def render_doc(
    path: Path,
    fmt: FormatName = 'pretty',
    max_chars: int = 12000,
    style: Style | None = None,
) -> str:
    s = style or Style()
    text = _read(path)
    title = f'{path}'
    if fmt == 'raw':
        body = text if len(text) <= max_chars else text[: max_chars - 1] + '…'
        return f'{header(title, s)}\n{body}'
    if fmt == 'toc':
        return header(f'TOC — {path.name}', s) + '\n' + markdown_toc(text)
    if fmt == 'outline':
        return header(f'Outline — {path.name}', s) + '\n' + markdown_outline(text, max_chars=max_chars)
    # pretty default = outline + path meta
    lines = [
        header(f'Doc — {path.name}', s),
        kv('path', str(path), s),
        kv('bytes', path.stat().st_size if path.is_file() else 0, s),
        hr(),
        markdown_outline(text, max_level=3, max_chars=max_chars),
    ]
    return '\n'.join(str(x) for x in lines)


def render_skills_cards(
    skills: list[SkillInfo] | None = None,
    paths: JuniePaths | None = None,
    style: Style | None = None,
    limit: int = 0,
) -> str:
    s = style or Style()
    items = skills if skills is not None else list_skills(paths)
    if limit > 0:
        items = items[:limit]
    lines = [header(f'Skills ({len(items)})', s)]
    rows = []
    for sk in items:
        flags = []
        if sk.has_skill_md:
            flags.append('SKILL')
        if sk.has_agents_junie:
            flags.append('junie')
        if sk.has_agents_claude:
            flags.append('claude')
        if sk.has_references:
            flags.append('refs')
        if sk.has_scripts:
            flags.append('scripts')
        desc = sk.description
        if len(desc) > 70:
            desc = desc[:67] + '…'
        rows.append((sk.name, ','.join(flags) or '-', desc))
    lines.append(table(rows, headers=('name', 'assets', 'description')))
    return '\n'.join(lines)


def render_commands_cards(
    commands: list[CommandInfo] | None = None,
    paths: JuniePaths | None = None,
    style: Style | None = None,
) -> str:
    s = style or Style()
    items = commands if commands is not None else list_commands(paths)
    lines = [header(f'Commands ({len(items)})', s)]
    rows = []
    warnings = 0
    for c in items:
        desc = c.description
        if len(desc) > 56:
            desc = desc[:53] + '…'
        mode = c.arg_mode
        if len(mode) > 36:
            mode = mode[:33] + '…'
        # flag catch-all ARGUMENTS without allowPrompt as broken UX
        bad = 'ARGUMENTS' in c.required_placeholders and not c.allow_prompt_argument
        if bad or (c.required_placeholders and 'ARGUMENTS' in c.required_placeholders):
            warnings += 1
            mode = f'! {mode}'
        rows.append((f'/{c.name}', mode, desc))
    lines.append(table(rows, headers=('command', 'args', 'description')))
    if warnings:
        lines.append(hr())
        lines.append(
            s.yellow(
                f'{warnings} command(s) use a required ARGUMENTS (or other) placeholder — '
                'bare /cmd will not run; prefer allowPromptArgument: true for CLI wrappers.'
            )
        )
    return '\n'.join(lines)


def render_docs_tree(paths: JuniePaths | None = None, style: Style | None = None) -> str:
    s = style or Style()
    p = paths or make_paths()
    lines = [header('Agent documentation tree', s)]
    lines.append(kv('home', p.home, s))
    docs = list_guideline_docs(p)
    # group by parent
    by_parent: dict[str, list[Path]] = {}
    for d in docs:
        try:
            rel = d.relative_to(p.home)
            parent = str(rel.parent)
        except ValueError:
            parent = str(d.parent)
            rel = d
        by_parent.setdefault(parent, []).append(d)
    for parent in sorted(by_parent):
        lines.append(s.bold(f'  {parent}/'))
        for f in by_parent[parent]:
            lines.append(f'    - {f.name}  ({f.stat().st_size} B)')
    proj = find_project_agents_roots()
    lines.append(hr())
    lines.append(s.bold('Project agent entrypoints (from cwd upward)'))
    if not proj:
        lines.append('  (none found)')
    else:
        for pr in proj:
            lines.append(f'  - {pr}')
    return '\n'.join(str(x) for x in lines)


def render_index(
    paths: JuniePaths | None = None,
    style: Style | None = None,
    *,
    include_skills: bool = True,
    include_commands: bool = True,
) -> str:
    s = style or Style()
    parts = [render_docs_tree(paths, s)]
    if include_commands:
        parts.append('')
        parts.append(render_commands_cards(paths=paths, style=s))
    if include_skills:
        parts.append('')
        parts.append(render_skills_cards(paths=paths, style=s))
    return '\n'.join(parts)
