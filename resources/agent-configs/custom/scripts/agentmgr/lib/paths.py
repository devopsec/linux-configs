"""Resolve agent home paths (Junie CLI, Claude Code) and optional project agent roots."""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from pathlib import Path

# agent_target.py lives in custom/scripts/, two levels above this package.
_SCRIPTS = Path(__file__).resolve().parent.parent.parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))
from agent_target import AGENTS, agent_home  # noqa: E402


def junie_home(explicit: str | Path | None = None) -> Path:
    return agent_home('junie', explicit)


@dataclass(frozen=True)
class AgentPaths:
    """Paths inside one agent's home. Layout is shared; entrypoint/config/MCP/sessions differ."""

    home: Path
    agent: str = 'junie'

    @property
    def label(self) -> str:
        return AGENTS[self.agent].label

    @property
    def tilde_home(self) -> str:
        """Home as written in docs and command bodies, e.g. ``~/.junie/``."""
        return AGENTS[self.agent].default_home.rstrip('/') + '/'

    @property
    def agent_doc(self) -> str:
        """Per-agent skill doc file under ``<skill>/agents/``."""
        return f'{self.agent}.md'

    @property
    def agents_md(self) -> Path:
        """Global instruction entrypoint: AGENTS.md (Junie) or CLAUDE.md (Claude Code)."""
        return self.home / ('CLAUDE.md' if self.agent == 'claude' else 'AGENTS.md')

    @property
    def config(self) -> Path:
        """Junie's config.json; Claude Code has none (settings.json only), so this never exists there."""
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
        """Junie: sessions/<id>/; Claude Code: projects/<encoded-cwd>/<id>.jsonl."""
        return self.home / ('projects' if self.agent == 'claude' else 'sessions')

    @property
    def mcp(self) -> Path:
        """Junie: mcp/mcp.json. Claude Code: ~/.claude.json (user-scope servers) for the default
        home, or <home>/.claude.json when the home is relocated (CLAUDE_CONFIG_DIR layout)."""
        if self.agent == 'claude':
            default = Path(AGENTS['claude'].default_home).expanduser().resolve()
            return self.home.parent / '.claude.json' if self.home == default else self.home / '.claude.json'
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


# Backwards-compatible name.
JuniePaths = AgentPaths


def make_paths(home: str | Path | None = None, agent: str = 'junie') -> AgentPaths:
    return AgentPaths(home=agent_home(agent, home), agent=agent)


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
