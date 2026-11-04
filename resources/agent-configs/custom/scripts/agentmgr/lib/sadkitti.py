"""SAD KITTI scan / lint / graph tooling.

Migrated from interconnect-governance testing/integ/sadkitti_{scan,lint,graph}.py
with improved path resolution (~, absolute paths).
"""

from __future__ import annotations

import re
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path

from .paths import expand_ref_path

BLOCK_PATTERN = re.compile(r'```sadkitti\n([\s\S]*?)```', re.MULTILINE)
REF_PATTERN = re.compile(r'(?:REFERENCE|REQUIRE)\s+"([^"]+)"')
IGNORE_MARKER = '<!-- sadkitti-lint: ignore -->'


def iter_markdown(root: Path) -> list[Path]:
    root = root.resolve()
    if root.is_file() and root.suffix == '.md':
        return [root]
    if not root.exists():
        return []
    return sorted(p for p in root.rglob('*.md') if p.is_file())


def scan_file(path: Path) -> list[dict]:
    text = path.read_text(encoding='utf-8', errors='replace')
    results = []
    for m in BLOCK_PATTERN.finditer(text):
        start_line = text[: m.start()].count('\n') + 1
        results.append(
            {
                'file': str(path),
                'line': start_line,
                'block': m.group(1).strip(),
            }
        )
    return results


def scan(root: Path) -> list[dict]:
    found: list[dict] = []
    for md in iter_markdown(root):
        found.extend(scan_file(md))
    return found


def format_scan(found: list[dict]) -> str:
    if not found:
        return 'No sadkitti blocks found.'
    lines: list[str] = []
    for entry in found:
        lines.append(f"\n--- {entry['file']} (line {entry['line']}) ---")
        lines.append(entry['block'])
    return '\n'.join(lines).lstrip('\n')


def lint_file(path: Path, root: Path) -> list[dict]:
    text = path.read_text(encoding='utf-8', errors='replace')
    if IGNORE_MARKER in text:
        return []
    errors = []
    for block_match in BLOCK_PATTERN.finditer(text):
        block = block_match.group(1)
        line_offset = text[: block_match.start()].count('\n') + 1
        for ref_match in REF_PATTERN.finditer(block):
            ref_path = ref_match.group(1)
            # skip obvious placeholders
            if 'PATH/TO' in ref_path or 'SKILL_NAME' in ref_path or ref_path.startswith('DOC_'):
                continue
            resolved = expand_ref_path(ref_path, root)
            if not resolved.exists():
                try:
                    rel_source = str(path.relative_to(root)) if root.is_dir() else str(path)
                except ValueError:
                    rel_source = str(path)
                errors.append(
                    {
                        'source': rel_source,
                        'line': line_offset,
                        'broken_ref': ref_path,
                        'resolved': str(resolved),
                    }
                )
    return errors


def lint(root: Path) -> list[dict]:
    root = root.resolve()
    all_errors: list[dict] = []
    for md in iter_markdown(root):
        # lint root for relative refs: use file's parent chain — prefer provided root
        lint_root = root if root.is_dir() else root.parent
        all_errors.extend(lint_file(md, lint_root))
    return all_errors


def format_lint(errors: list[dict]) -> tuple[str, int]:
    if not errors:
        return 'sadkitti lint: OK — all references resolved.', 0
    lines = [f'sadkitti lint: FAILED — {len(errors)} broken reference(s):', '']
    for e in errors:
        lines.append(f"  [{e['source']}:{e['line']}] broken -> \"{e['broken_ref']}\"")
    return '\n'.join(lines), 1


def build_graph(root: Path) -> dict[str, set[str]]:
    root = root.resolve()
    graph: dict[str, set[str]] = defaultdict(set)
    base = root if root.is_dir() else root.parent
    for md in iter_markdown(root):
        try:
            rel_source = str(md.relative_to(base))
        except ValueError:
            rel_source = str(md)
        text = md.read_text(encoding='utf-8', errors='replace')
        for block_match in BLOCK_PATTERN.finditer(text):
            for ref_match in REF_PATTERN.finditer(block_match.group(1)):
                graph[rel_source].add(ref_match.group(1))
    return dict(graph)


def format_graph_text(graph: dict[str, set[str]], root: Path | None = None) -> str:
    if not graph:
        return 'No sadkitti references found.'
    base = root.resolve() if root else Path.cwd()
    lines = ['SAD KITTI Documentation Dependency Graph', '']
    for source, targets in sorted(graph.items()):
        for target in sorted(targets):
            resolved = expand_ref_path(target, base if base.is_dir() else base.parent)
            exists = '' if resolved.exists() else ' [MISSING]'
            lines.append(f'  {source}  -->  {target}{exists}')
    return '\n'.join(lines)


def build_plantuml(graph: dict[str, set[str]]) -> str:
    lines = ['@startuml', 'left to right direction', '']
    nodes: set[str] = set()
    edges: list[tuple[str, str]] = []
    for source, targets in graph.items():
        nodes.add(source)
        for target in targets:
            nodes.add(target)
            edges.append((source, target))
    alias_map: dict[str, str] = {}
    for i, node in enumerate(sorted(nodes)):
        alias = f'N{i}'
        alias_map[node] = alias
        label = node.replace('"', "'")
        lines.append(f'component "{label}" as {alias}')
    lines.append('')
    for src, tgt in sorted(edges):
        lines.append(f'{alias_map[src]} --> {alias_map[tgt]}')
    lines.append('')
    lines.append('@enduml')
    return '\n'.join(lines)


def build_mermaid(graph: dict[str, set[str]]) -> str:
    lines = ['flowchart LR']
    # mermaid node ids
    nodes: set[str] = set()
    edges: list[tuple[str, str]] = []
    for source, targets in graph.items():
        nodes.add(source)
        for t in targets:
            nodes.add(t)
            edges.append((source, t))

    def nid(label: str) -> str:
        return 'n' + re.sub(r'[^a-zA-Z0-9]', '_', label)[:60]

    for n in sorted(nodes):
        safe = n.replace('"', "'")
        if len(safe) > 40:
            safe = safe[:37] + '…'
        lines.append(f'  {nid(n)}["{safe}"]')
    for a, b in sorted(edges):
        lines.append(f'  {nid(a)} --> {nid(b)}')
    return '\n'.join(lines)


def render_image(graph: dict[str, set[str]], fmt: str, output: Path) -> None:
    if not graph:
        raise RuntimeError('No sadkitti references found.')
    puml_src = build_plantuml(graph)
    flag = '-tsvg' if fmt == 'svg' else '-tpng'
    result = subprocess.run(
        ['plantuml', flag, '-pipe'],
        input=puml_src.encode(),
        capture_output=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f'plantuml error: {result.stderr.decode(errors="replace")}')
    output.write_bytes(result.stdout)


def render_via_pandoc(graph: dict[str, set[str]], output: Path) -> None:
    if not graph:
        raise RuntimeError('No sadkitti references found.')
    puml_src = build_plantuml(graph)
    md_content = f'# SAD KITTI Dependency Graph\n\n```plantuml\n{puml_src}\n```\n'
    with tempfile.NamedTemporaryFile(suffix='.md', mode='w', delete=False, encoding='utf-8') as tmp:
        tmp.write(md_content)
        tmp_path = Path(tmp.name)
    try:
        cmd = ['pandoc', str(tmp_path), '-o', str(output), '--from', 'markdown', '--standalone']
        for candidate in ('pandoc-plantuml', 'pandoc-plot', 'pandoc-crossref'):
            if subprocess.run(['which', candidate], capture_output=True).returncode == 0:
                cmd += ['--filter', candidate]
                break
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f'pandoc error: {result.stderr}')
    finally:
        tmp_path.unlink(missing_ok=True)
