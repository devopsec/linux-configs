"""Terminal pretty-printing helpers (no third-party deps)."""

from __future__ import annotations

import os
import re
import shutil
import textwrap
from typing import Iterable, Sequence


def use_color(stream_isatty: bool | None = None) -> bool:
    if os.environ.get('NO_COLOR'):
        return False
    if os.environ.get('FORCE_COLOR'):
        return True
    if stream_isatty is None:
        stream_isatty = hasattr(os, 'isatty') and False
    try:
        import sys

        return sys.stdout.isatty() if stream_isatty is None else bool(stream_isatty)
    except Exception:
        return False


class Style:
    def __init__(self, enabled: bool | None = None) -> None:
        if enabled is None:
            try:
                import sys

                enabled = sys.stdout.isatty() and not os.environ.get('NO_COLOR')
            except Exception:
                enabled = False
        self.enabled = bool(enabled)

    def _wrap(self, code: str, text: str) -> str:
        if not self.enabled:
            return text
        return f'\033[{code}m{text}\033[0m'

    def bold(self, t: str) -> str:
        return self._wrap('1', t)

    def dim(self, t: str) -> str:
        return self._wrap('2', t)

    def cyan(self, t: str) -> str:
        return self._wrap('36', t)

    def green(self, t: str) -> str:
        return self._wrap('32', t)

    def yellow(self, t: str) -> str:
        return self._wrap('33', t)

    def red(self, t: str) -> str:
        return self._wrap('31', t)

    def magenta(self, t: str) -> str:
        return self._wrap('35', t)


def term_width(default: int = 88) -> int:
    try:
        return max(40, shutil.get_terminal_size((default, 20)).columns)
    except Exception:
        return default


def hr(char: str = '─', width: int | None = None) -> str:
    w = width or term_width()
    return char * min(w, 100)


def header(title: str, style: Style | None = None) -> str:
    s = style or Style()
    return f'{s.bold(title)}\n{hr()}'


def kv(key: str, value: object, style: Style | None = None, key_width: int = 18) -> str:
    s = style or Style()
    k = s.cyan(f'{key:<{key_width}}')
    return f'{k} {value}'


def bullet_list(items: Iterable[str], indent: int = 2) -> str:
    pad = ' ' * indent
    return '\n'.join(f'{pad}• {item}' for item in items)


def table(rows: Sequence[Sequence[str]], headers: Sequence[str] | None = None) -> str:
    data: list[Sequence[str]] = list(rows)
    if headers:
        data = [list(headers), *data]
    if not data:
        return ''
    cols = len(data[0])
    widths = [0] * cols
    for row in data:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(str(cell)))
    lines: list[str] = []
    for idx, row in enumerate(data):
        line = '  '.join(str(cell).ljust(widths[i]) for i, cell in enumerate(row))
        lines.append(line.rstrip())
        if headers and idx == 0:
            lines.append('  '.join('─' * widths[i] for i in range(cols)))
    return '\n'.join(lines)


def wrap_text(text: str, width: int | None = None, indent: str = '') -> str:
    w = (width or term_width()) - len(indent)
    parts = []
    for para in text.splitlines() or ['']:
        if not para.strip():
            parts.append('')
            continue
        parts.append(textwrap.fill(para, width=max(20, w), subsequent_indent=indent))
    return '\n'.join(parts)


_MD_HEADING = re.compile(r'^(#{1,6})\s+(.*)$')


def markdown_toc(md: str, max_level: int = 3) -> str:
    lines = []
    for line in md.splitlines():
        m = _MD_HEADING.match(line)
        if not m:
            continue
        level = len(m.group(1))
        if level > max_level:
            continue
        title = m.group(2).strip()
        pad = '  ' * (level - 1)
        lines.append(f'{pad}- {title}')
    return '\n'.join(lines) if lines else '(no headings)'


def markdown_outline(md: str, max_level: int = 2, max_chars: int = 4000) -> str:
    """Compact outline: headings + first non-empty paragraph under each."""
    out: list[str] = []
    current_level = 0
    took_blurb = True
    total = 0
    for line in md.splitlines():
        m = _MD_HEADING.match(line)
        if m:
            level = len(m.group(1))
            if level <= max_level:
                block = f'{m.group(1)} {m.group(2).strip()}'
                out.append(block)
                total += len(block)
                current_level = level
                took_blurb = False
            continue
        if not took_blurb and line.strip() and not line.strip().startswith('```'):
            blurb = line.strip()
            if len(blurb) > 160:
                blurb = blurb[:157] + '…'
            indented = f'  {blurb}'
            out.append(indented)
            total += len(indented)
            took_blurb = True
        if total >= max_chars:
            out.append('…')
            break
    return '\n'.join(out)
