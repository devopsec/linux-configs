"""Audit agent workflow / token usage from session events.jsonl.

Migrated and extended from interconnect-governance testing/integ/agent_workflow_test.py.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

from .paths import JuniePaths, make_paths
from .pretty import Style, header, hr, kv


@dataclass
class WorkflowAudit:
    events_file: Path
    events: list[dict[str, Any]] = field(default_factory=list)
    total_cost: float = 0.0
    total_input_tokens: int = 0
    total_output_tokens: int = 0
    total_cached_tokens: int = 0
    workflow_steps: list[dict[str, Any]] = field(default_factory=list)
    guideline_references: list[dict[str, Any]] = field(default_factory=list)
    tool_counts: dict[str, int] = field(default_factory=dict)
    errors: list[str] = field(default_factory=list)

    def load_events(self) -> None:
        if not self.events_file.exists():
            raise FileNotFoundError(f'{self.events_file} not found')
        with self.events_file.open('r', encoding='utf-8') as f:
            for line_no, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    self.events.append(json.loads(line))
                except json.JSONDecodeError as exc:
                    self.errors.append(f'line {line_no}: {exc}')

    def parse_workflow(self) -> None:
        for entry in self.events:
            if entry.get('kind') != 'SessionA2uxEvent':
                # also accept already-unwrapped agent events
                agent_event = entry.get('agentEvent') or entry.get('event', {}).get('agentEvent')
                if not agent_event and 'event' not in entry:
                    continue
            agent_event = entry.get('event', {}).get('agentEvent', {})
            if not agent_event and isinstance(entry.get('agentEvent'), dict):
                agent_event = entry['agentEvent']
            kind = agent_event.get('kind')
            timestamp = entry.get('timestampMs', 0)

            if kind == 'LlmResponseMetadataEvent':
                usage = agent_event.get('modelUsage', []) or []
                for u in usage:
                    self.total_cost += float(u.get('cost', 0) or 0)
                    self.total_input_tokens += int(u.get('inputTokens', 0) or 0)
                    self.total_output_tokens += int(u.get('outputTokens', 0) or 0)
                    self.total_cached_tokens += int(u.get('cacheInputTokens', 0) or 0)

            elif kind == 'ToolBlockUpdatedEvent':
                if agent_event.get('status') == 'IN_PROGRESS':
                    name = agent_event.get('text', 'Unknown Tool')
                    self.workflow_steps.append(
                        {
                            'type': 'tool',
                            'name': name,
                            'timestamp': timestamp,
                            'stepId': agent_event.get('stepId'),
                        }
                    )
                    self.tool_counts[name] = self.tool_counts.get(name, 0) + 1
                text = agent_event.get('text', '') or ''
                if 'REFERENCE' in text or 'REQUIRE' in text:
                    self.guideline_references.append({'text': text, 'timestamp': timestamp})

            elif kind == 'TerminalBlockUpdatedEvent':
                if 'command' in agent_event and agent_event.get('status') == 'IN_PROGRESS':
                    self.workflow_steps.append(
                        {
                            'type': 'terminal',
                            'name': agent_event.get('command'),
                            'timestamp': timestamp,
                        }
                    )

            elif kind == 'AgentThoughtBlockUpdatedEvent':
                thought = agent_event.get('text', '') or ''
                if 'JUMP' in thought or 'RET' in thought or 'sadkitti' in thought.lower():
                    detail = thought[:100] + ('…' if len(thought) > 100 else '')
                    self.workflow_steps.append(
                        {
                            'type': 'thought',
                            'name': 'SAD KITTI Context Switch',
                            'detail': detail,
                            'timestamp': timestamp,
                        }
                    )

    @property
    def cache_hit_rate(self) -> float:
        denom = self.total_input_tokens + self.total_cached_tokens
        if denom <= 0:
            return 0.0
        return (self.total_cached_tokens / denom) * 100.0

    def summary_dict(self) -> dict[str, Any]:
        return {
            'events_file': str(self.events_file),
            'events_loaded': len(self.events),
            'parse_errors': len(self.errors),
            'total_cost': round(self.total_cost, 6),
            'total_input_tokens': self.total_input_tokens,
            'total_output_tokens': self.total_output_tokens,
            'total_cached_tokens': self.total_cached_tokens,
            'cache_hit_rate_pct': round(self.cache_hit_rate, 2),
            'workflow_steps': len(self.workflow_steps),
            'guideline_references': len(self.guideline_references),
            'tool_counts': dict(sorted(self.tool_counts.items(), key=lambda kv: (-kv[1], kv[0]))),
            'guideline_ok': bool(self.guideline_references),
        }

    def print_summary(self, style: Style | None = None) -> str:
        s = style or Style()
        lines = [
            header('Agent Workflow Execution Summary', s),
            kv('events file', self.events_file, s),
            kv('events', len(self.events), s),
            kv('total cost', f'${self.total_cost:.4f}', s),
            kv('input tokens', self.total_input_tokens, s),
            kv('output tokens', self.total_output_tokens, s),
            kv('cached tokens', self.total_cached_tokens, s),
            kv('cache hit rate', f'{self.cache_hit_rate:.2f}%', s),
            kv('workflow steps', len(self.workflow_steps), s),
            hr(),
            s.bold('Guideline Interlock Audit'),
        ]
        if not self.guideline_references:
            lines.append(s.yellow('WARNING: No guideline REFERENCE or REQUIRE calls detected!'))
        else:
            for ref in self.guideline_references[:50]:
                ts = ref['timestamp']
                try:
                    tstr = datetime.fromtimestamp(ts / 1000).strftime('%H:%M:%S') if ts else '??:??:??'
                except (OSError, ValueError, OverflowError):
                    tstr = str(ts)
                text = ref['text']
                if len(text) > 120:
                    text = text[:117] + '…'
                lines.append(f'  [{tstr}] {text}')
            if len(self.guideline_references) > 50:
                lines.append(f'  … +{len(self.guideline_references) - 50} more')
        if self.tool_counts:
            lines.append(hr())
            lines.append(s.bold('Top tools'))
            for name, count in sorted(self.tool_counts.items(), key=lambda kv: (-kv[1], kv[0]))[:15]:
                lines.append(f'  {count:4d}  {name}')
        if self.errors:
            lines.append(hr())
            lines.append(s.red(f'Parse errors: {len(self.errors)}'))
            for e in self.errors[:5]:
                lines.append(f'  {e}')
        return '\n'.join(str(x) for x in lines)

    def generate_mermaid(self, limit: int = 80) -> str:
        lines = ['flowchart TD']
        steps = self.workflow_steps[:limit]
        for i, step in enumerate(steps):
            name = str(step.get('name', '')).replace('"', "'").replace('[', '(').replace(']', ')')
            if len(name) > 60:
                name = name[:57] + '…'
            lines.append(f'  S{i}[{step.get("type", "?").upper()}: {name}]')
            if i > 0:
                lines.append(f'  S{i - 1} --> S{i}')
        if len(self.workflow_steps) > limit:
            lines.append(f'  S{limit - 1} --> SX[… {len(self.workflow_steps) - limit} more]')
        return '\n'.join(lines)


def resolve_events_file(spec: str, paths: JuniePaths | None = None) -> Path:
    """Accept path, session id, or 'latest'."""
    p = paths or make_paths()
    raw = spec.strip()
    if raw in ('latest', 'last', '@latest'):
        sessions = sorted(
            (d for d in p.sessions.iterdir() if d.is_dir() and (d / 'events.jsonl').is_file()),
            key=lambda d: d.stat().st_mtime,
            reverse=True,
        )
        if not sessions:
            raise FileNotFoundError(f'no sessions with events.jsonl under {p.sessions}')
        return sessions[0] / 'events.jsonl'
    path = Path(raw).expanduser()
    if path.is_file():
        return path.resolve()
    # session id
    sid = raw
    if not sid.startswith('session-'):
        # try prefix match
        matches = [
            d
            for d in p.sessions.iterdir()
            if d.is_dir() and (sid in d.name) and (d / 'events.jsonl').is_file()
        ]
        if len(matches) == 1:
            return matches[0] / 'events.jsonl'
        if len(matches) > 1:
            raise FileNotFoundError(f'ambiguous session id {sid!r}: {[m.name for m in matches[:5]]}')
    cand = p.sessions / sid / 'events.jsonl'
    if cand.is_file():
        return cand
    raise FileNotFoundError(f'cannot resolve events file from {spec!r}')


def run_audit(
    events_spec: str,
    paths: JuniePaths | None = None,
    *,
    mermaid: bool = False,
    as_json: bool = False,
) -> str:
    events_file = resolve_events_file(events_spec, paths)
    audit = WorkflowAudit(events_file=events_file)
    audit.load_events()
    audit.parse_workflow()
    if as_json:
        data = audit.summary_dict()
        if mermaid:
            data['mermaid'] = audit.generate_mermaid()
        return json.dumps(data, indent=2)
    out = audit.print_summary()
    if mermaid:
        out += '\n' + hr() + '\n=== Mermaid Flowchart ===\n' + audit.generate_mermaid()
    return out
