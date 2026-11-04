"""Agent logic steering and decision-routing helpers."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from textwrap import dedent

from .paths import JuniePaths, make_paths
from .pretty import Style, header, hr, table

BLOCK_RE = re.compile(r'```sadkitti\n([\s\S]*?)```', re.MULTILINE)
PRIM_RE = re.compile(
    r'\b(REFERENCE|REQUIRE|CACHE|ABORT|IF|ELSE|EXTRACT|JUMP|RET)\b'
)


@dataclass
class RoutingBlock:
    file: str
    line: int
    primitives: list[str]
    preview: str


STEERING_TEMPLATES: dict[str, str] = {
    'domain-routing': dedent(
        '''\
        ```sadkitti
        IF task domain is "bash"
          REFERENCE "~/.junie/custom/docs/bash-guidelines.md"
        ELSE IF task domain is "python"
          REFERENCE "~/.junie/custom/docs/python-guidelines.md"
        ELSE IF task domain is "infrastructure"
          REFERENCE "~/.junie/custom/docs/infrastructure-guidelines.md"
        ELSE IF task domain is "security"
          REFERENCE "~/.junie/custom/docs/security-guidelines.md"
        ELSE IF task domain is "testing"
          REFERENCE "~/.junie/custom/docs/testing-guidelines.md"
        ```
        '''
    ).rstrip(),
    'skill-gate': dedent(
        '''\
        ```sadkitti
        IF user intent matches skill triggers for "SKILL_NAME"
          REQUIRE "skills/SKILL_NAME/SKILL.md"
          REFERENCE "skills/SKILL_NAME/SKILL.md" EXTRACT workflow only
          CACHE skill workflow for this task
        ELSE
          continue without that skill
        ```
        '''
    ).rstrip(),
    'project-over-global': dedent(
        '''\
        ```sadkitti
        IF project-level AGENTS.md exists
          REQUIRE project "AGENTS.md"
          CACHE project agent rules — they override global fallbacks on conflict
        ELSE
          REQUIRE "~/.junie/AGENTS.md"
        ```
        '''
    ).rstrip(),
    'interlock-require': dedent(
        '''\
        ```sadkitti
        REQUIRE "PATH/TO/REQUIRED.md"
        IF file is missing or unreadable -> ABORT with message: "Required doc missing — cannot proceed."
        ```
        '''
    ).rstrip(),
    'decision-matrix': dedent(
        '''\
        ```sadkitti
        IF change is documentation-only
          skip build and tests
        ELSE IF change is trivial single-file
          prefer FAST path; targeted verify only
        ELSE IF change touches infrastructure or secrets surface
          REQUIRE security guidelines
          REFERENCE "~/.junie/custom/docs/security-guidelines.md"
        ELSE
          follow standard CODE workflow with proportional tests
        ```
        '''
    ).rstrip(),
    'command-intent-map': dedent(
        '''\
        # Command intent map (agent-facing)
        # Map natural language after /command to subcommands.

        | User says | Subcommand |
        |-----------|------------|
        | status / overview | status |
        | show docs / pretty print | docs |
        | list skills | skills list |
        | tune model / budget | tune show |
        | sadkitti lint | sadkitti lint |
        | audit workflow / tokens | workflow audit |
        '''
    ).rstrip(),
}


def list_templates() -> list[str]:
    return sorted(STEERING_TEMPLATES)


def get_template(name: str) -> str:
    if name not in STEERING_TEMPLATES:
        known = ', '.join(list_templates())
        raise KeyError(f'unknown template {name!r}; known: {known}')
    return STEERING_TEMPLATES[name]


def scan_routing_blocks(root: Path) -> list[RoutingBlock]:
    root = root.resolve()
    found: list[RoutingBlock] = []
    if root.is_file() and root.suffix == '.md':
        files = [root]
    else:
        files = sorted(root.rglob('*.md'))
    for md in files:
        try:
            text = md.read_text(encoding='utf-8', errors='replace')
        except OSError:
            continue
        for m in BLOCK_RE.finditer(text):
            block = m.group(1)
            line = text[: m.start()].count('\n') + 1
            prims = sorted(set(PRIM_RE.findall(block)))
            preview = ' '.join(block.strip().split())
            if len(preview) > 100:
                preview = preview[:97] + '…'
            try:
                rel = str(md.relative_to(root)) if root.is_dir() else str(md)
            except ValueError:
                rel = str(md)
            found.append(RoutingBlock(file=rel, line=line, primitives=prims, preview=preview))
    return found


def render_routing_report(blocks: list[RoutingBlock], style: Style | None = None) -> str:
    s = style or Style()
    lines = [header(f'Decision-routing blocks ({len(blocks)})', s), hr()]
    if not blocks:
        lines.append('No ```sadkitti blocks found.')
        return '\n'.join(lines)
    rows = []
    for b in blocks:
        rows.append((f'{b.file}:{b.line}', ','.join(b.primitives) or '-', b.preview))
    lines.append(table(rows, headers=('location', 'primitives', 'preview')))
    return '\n'.join(lines)


def scaffold_steering_doc(
    name: str,
    templates: list[str],
    output: Path,
    *,
    dry_run: bool = True,
) -> str:
    """Write a steering markdown doc composed of named templates."""
    parts = [
        f'# Agent steering — {name}',
        '',
        'Generated by `agentmgr steer scaffold`. Edit before committing to a project.',
        '',
    ]
    for t in templates:
        parts.append(f'## Template: {t}')
        parts.append('')
        parts.append(get_template(t))
        parts.append('')
    body = '\n'.join(parts)
    if dry_run:
        return body
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise FileExistsError(f'refusing to overwrite existing {output}')
    output.write_text(body + '\n', encoding='utf-8')
    return body


def default_scan_roots(paths: JuniePaths | None = None) -> list[Path]:
    p = paths or make_paths()
    roots = [p.agents_md, p.custom_docs]
    return [r for r in roots if r.exists()]
