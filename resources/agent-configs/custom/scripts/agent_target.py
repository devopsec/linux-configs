"""Resolve which coding agent (Junie CLI or Claude Code) a tool operates on.

Shared by agentmgr and histmgr. Resolution order:
  1. explicit ``--agent NAME``
  2. ``AGENT_TARGET`` environment variable
  3. the agent that launched this process (Claude Code exports ``CLAUDECODE``;
     Junie exports its session variables)
  4. the only agent installed (its home directory exists)
  5. an interactive prompt when stdin and stderr are terminals (standalone use)
  6. otherwise ``AgentSelectionError`` (callers exit 2 with the message)
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import TextIO

ENV_AGENT = 'AGENT_TARGET'


@dataclass(frozen=True)
class AgentSpec:
    name: str
    label: str
    home_envs: tuple[str, ...]
    default_home: str
    detect_envs: tuple[str, ...]


AGENTS: dict[str, AgentSpec] = {
    'junie': AgentSpec(
        name='junie',
        label='Junie CLI',
        home_envs=('JUNIE_HOME',),
        default_home='~/.junie',
        detect_envs=('JUNIE_SESSION_ID', 'JUNIE_SESSION', 'JUNIE_CURRENT_SESSION'),
    ),
    'claude': AgentSpec(
        name='claude',
        label='Claude Code',
        home_envs=('CLAUDE_HOME', 'CLAUDE_CONFIG_DIR'),
        default_home='~/.claude',
        detect_envs=('CLAUDECODE', 'CLAUDE_CODE_SESSION_ID'),
    ),
}
AGENT_NAMES = tuple(AGENTS)


class AgentSelectionError(RuntimeError):
    """No target agent could be determined without asking."""


def agent_home(agent: str, explicit: str | Path | None = None) -> Path:
    """Home directory of ``agent``: explicit path, then its env vars, then the default."""
    if explicit:
        return Path(explicit).expanduser().resolve()
    spec = AGENTS[agent]
    for env in spec.home_envs:
        val = os.environ.get(env)
        if val:
            return Path(val).expanduser().resolve()
    return Path(spec.default_home).expanduser().resolve()


def detect_calling_agent() -> str | None:
    """The agent whose process tree we run in, if it identifies itself in the environment."""
    for name, spec in AGENTS.items():
        if any(os.environ.get(env) for env in spec.detect_envs):
            return name
    return None


def installed_agents() -> list[str]:
    return [name for name in AGENT_NAMES if agent_home(name).is_dir()]


def _validate(name: str, source: str) -> str:
    key = name.strip().lower()
    if key not in AGENTS:
        raise AgentSelectionError(f'unknown agent {name!r} from {source}; choose one of: {", ".join(AGENT_NAMES)}')
    return key


def prompt_agent(stdin: TextIO, stderr: TextIO, purpose: str = '') -> str:
    """Ask on the terminal which agent to target; accepts a number or a name."""
    choices = list(AGENT_NAMES)
    print(f'Target agent{f" for {purpose}" if purpose else ""}:', file=stderr)
    for i, name in enumerate(choices, start=1):
        spec = AGENTS[name]
        home = agent_home(name)
        mark = '' if home.is_dir() else '  (not installed)'
        print(f'  {i}) {name:<7} {spec.label:<12} {home}{mark}', file=stderr)
    for _ in range(3):
        print(f'Choose [1-{len(choices)}] or name: ', end='', file=stderr, flush=True)
        answer = stdin.readline()
        if not answer:
            break
        answer = answer.strip().lower()
        if answer.isdigit() and 1 <= int(answer) <= len(choices):
            return choices[int(answer) - 1]
        if answer in AGENTS:
            return answer
        print(f'invalid choice: {answer!r}', file=stderr)
    raise AgentSelectionError('no target agent chosen')


def resolve_agent(
    explicit: str | None = None,
    *,
    purpose: str = '',
    interactive: bool = True,
    stdin: TextIO | None = None,
    stderr: TextIO | None = None,
) -> str:
    """Return the agent name to operate on (see module docstring for the order)."""
    stdin = stdin or sys.stdin
    stderr = stderr or sys.stderr
    if explicit:
        return _validate(explicit, '--agent')
    env = os.environ.get(ENV_AGENT)
    if env:
        return _validate(env, ENV_AGENT)
    caller = detect_calling_agent()
    if caller:
        return caller
    present = installed_agents()
    if len(present) == 1:
        return present[0]
    if interactive and stdin.isatty() and stderr.isatty():
        return prompt_agent(stdin, stderr, purpose)
    raise AgentSelectionError(
        f'cannot tell which agent to target ({", ".join(present) or "none"} installed); '
        f'pass --agent {{{",".join(AGENT_NAMES)}}} or set {ENV_AGENT}'
    )
