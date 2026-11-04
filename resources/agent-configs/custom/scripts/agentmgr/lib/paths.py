"""Resolve Junie home paths and optional project agent roots."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def junie_home(explicit: str | Path | None = None) -> Path:
    if explicit:
        return Path(explicit).expanduser().resolve()
    env = os.environ.get('JUNIE_HOME')
    if env:
        return Path(env).expanduser().resolve()
    return (Path.home() / '.junie').resolve()


@dataclass(frozen=True)
class JuniePaths:
    home: Path

    @property
    def agents_md(self) -> Path:
        return self.home / 'AGENTS.md'

    @property
    def config(self) -> Path:
        return self.home / 'config.json'

    @property
    def settings(self) -> Path:
        return self.home / 'settings.json'

    @property
    def allowlist(self) -> Path:
        return self.home / 'allowlist.json'

    @property
    def skills(self) -> Path:
        return self.home / 'skills'

    @property
    def commands(self) -> Path:
        return self.home / 'commands'

    @property
    def bin(self) -> Path:
        """Direct CLI shims (agentmgr/histmgr/sectool) for zero-LLM runs."""
        return self.home / 'custom' / 'bin'

    @property
    def custom_docs(self) -> Path:
        return self.home / 'custom' / 'docs'

    @property
    def sadkitti(self) -> Path:
        return self.custom_docs / 'sadkitti'

    @property
    def scripts(self) -> Path:
        return self.home / 'custom' / 'scripts'

    @property
    def sessions(self) -> Path:
        return self.home / 'sessions'

    @property
    def mcp(self) -> Path:
        return self.home / 'mcp' / 'mcp.json'

    @property
    def models(self) -> Path:
        return self.home / 'models'

    @property
    def versions(self) -> Path:
        return self.home / 'versions'

    @property
    def validate_py(self) -> Path:
        return self.skills / 'dev-agents-skill-create' / 'scripts' / 'validate.py'

    @property
    def skills_catalog(self) -> Path:
        return self.custom_docs / 'skills-catalog.md'

    @property
    def commands_catalog(self) -> Path:
        return self.custom_docs / 'commands-catalog.md'

    @property
    def general_guidelines(self) -> Path:
        return self.custom_docs / 'general-guidelines.md'


def make_paths(home: str | Path | None = None) -> JuniePaths:
    return JuniePaths(home=junie_home(home))


def find_project_agents_roots(start: Path | None = None) -> list[Path]:
    """Walk upward from start (or cwd) looking for project agent entrypoints."""
    cur = (start or Path.cwd()).resolve()
    found: list[Path] = []
    seen: set[Path] = set()
    for base in [cur, *cur.parents]:
        if base in seen:
            break
        seen.add(base)
        candidates = [
            base / 'AGENTS.md',
            base / '.junie' / 'AGENTS.md',
            base / '.agents' / 'AGENTS.md',
            base / 'documentation' / 'agent' / 'AGENTS.md',
        ]
        for c in candidates:
            if c.is_file():
                found.append(c)
        # stop at filesystem root-ish after a few levels if nothing
        if len(seen) > 12:
            break
    # de-dupe preserving order
    out: list[Path] = []
    for p in found:
        if p not in out:
            out.append(p)
    return out


def expand_ref_path(ref: str, root: Path) -> Path:
    """Resolve REFERENCE/REQUIRE paths including ~ and absolute paths."""
    raw = ref.strip()
    if raw.startswith('~/') or raw == '~':
        return Path(raw).expanduser().resolve()
    p = Path(raw)
    if p.is_absolute():
        return p.resolve()
    return (root / raw).resolve()
