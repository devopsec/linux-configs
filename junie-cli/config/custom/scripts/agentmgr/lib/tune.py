"""Agent tuning helpers (budgets, models, effort, brave mode)."""

from __future__ import annotations

import json
from typing import Any

from .config_ops import apply_set, load_json
from .paths import JuniePaths, make_paths
from .pretty import Style, header, hr, kv, table


def _parse_effort_map(raw: Any) -> dict[str, str]:
    if raw is None:
        return {}
    if isinstance(raw, dict):
        return {str(k): str(v) for k, v in raw.items()}
    if isinstance(raw, str):
        try:
            data = json.loads(raw)
            if isinstance(data, dict):
                return {str(k): str(v) for k, v in data.items()}
        except json.JSONDecodeError:
            return {'_raw': raw}
    return {'_error': repr(raw)}


def tuning_snapshot(paths: JuniePaths | None = None) -> dict[str, Any]:
    p = paths or make_paths()
    cfg = load_json(p.config) if p.config.is_file() else {}
    settings = load_json(p.settings) if p.settings.is_file() else {}
    effort = _parse_effort_map(settings.get('effortPerModel'))
    return {
        'config_path': str(p.config),
        'settings_path': str(p.settings),
        'token_budget': cfg.get('token-budget'),
        'time_limit': cfg.get('time-limit'),
        'brave_config_flag': cfg.get('brave'),
        'braveMode': settings.get('braveMode'),
        'provider_config': cfg.get('provider'),
        'provider_settings': settings.get('provider'),
        'model': settings.get('model'),
        'modelForLaunch': settings.get('modelForLaunch'),
        'subagentsMode': settings.get('subagentsMode'),
        'ecoMode': settings.get('ecoMode'),
        'eventDensityMode': settings.get('eventDensityMode'),
        'diffViewMode': settings.get('diffViewMode'),
        'effortPerModel': effort,
        'effort_count': len(effort),
    }


def render_tuning(snap: dict[str, Any] | None = None, style: Style | None = None) -> str:
    s = style or Style()
    snap = snap or tuning_snapshot()
    lines = [
        header('Agent tuning snapshot', s),
        kv('token-budget', snap.get('token_budget'), s),
        kv('time-limit', snap.get('time_limit'), s),
        kv('brave (config)', snap.get('brave_config_flag'), s),
        kv('braveMode', snap.get('braveMode'), s),
        kv('provider cfg', snap.get('provider_config'), s),
        kv('provider set', snap.get('provider_settings'), s),
        kv('model', snap.get('model'), s),
        kv('modelForLaunch', snap.get('modelForLaunch'), s),
        kv('subagentsMode', snap.get('subagentsMode'), s),
        kv('ecoMode', snap.get('ecoMode'), s),
        kv('eventDensity', snap.get('eventDensityMode'), s),
        kv('diffViewMode', snap.get('diffViewMode'), s),
        hr(),
        s.bold(f'effortPerModel ({snap.get("effort_count", 0)} entries)'),
    ]
    effort = snap.get('effortPerModel') or {}
    if not effort:
        lines.append('  (empty)')
    else:
        rows = [(k, v) for k, v in sorted(effort.items(), key=lambda kv: kv[0].lower())]
        lines.append(table(rows, headers=('model', 'effort')))
    return '\n'.join(str(x) for x in lines)


def set_effort(
    model: str,
    effort: str,
    paths: JuniePaths | None = None,
    *,
    dry_run: bool = True,
    backup: bool = True,
    force: bool = False,
) -> dict[str, Any]:
    """Update one model effort level inside settings.effortPerModel JSON string."""
    allowed = {'none', 'low', 'medium', 'high'}
    eff = effort.strip().lower()
    if eff not in allowed:
        raise ValueError(f'effort must be one of {sorted(allowed)}')
    p = paths or make_paths()
    settings = load_json(p.settings) if p.settings.is_file() else {}
    effort_map = _parse_effort_map(settings.get('effortPerModel'))
    effort_map = {k: v for k, v in effort_map.items() if not k.startswith('_')}
    old = effort_map.get(model)
    effort_map[model] = eff
    # settings stores this as a JSON string historically
    new_raw = json.dumps(effort_map, separators=(',', ':'))
    result = apply_set(
        'settings',
        'effortPerModel',
        new_raw,
        paths=p,
        dry_run=dry_run,
        force=force,
        backup=backup,
    )
    result['model'] = model
    result['effort_old'] = old
    result['effort_new'] = eff
    return result


def recommend_tuning(snap: dict[str, Any] | None = None) -> list[str]:
    """Heuristic recommendations (non-destructive)."""
    snap = snap or tuning_snapshot()
    tips: list[str] = []
    tb = snap.get('token_budget')
    if isinstance(tb, int) and tb > 5_000_000:
        tips.append('token-budget is very high; consider lowering if you see cache thrash or cost spikes.')
    if isinstance(tb, int) and tb < 200_000:
        tips.append('token-budget looks low for multi-skill sessions; raise if tasks abort early.')
    tl = snap.get('time_limit')
    if isinstance(tl, int) and tl < 300:
        tips.append('time-limit under 5 minutes may cut off multi-step CODE workflows.')
    if str(snap.get('braveMode', '')).upper() == 'ON' and snap.get('brave_config_flag') is False:
        tips.append('settings.braveMode is ON but config.brave is false — confirm which flag Junie honors.')
    if snap.get('subagentsMode') == 'SameModelOnly':
        tips.append('subagentsMode=SameModelOnly: fine for consistency; switch only if you need tiered subagents.')
    effort = snap.get('effortPerModel') or {}
    high = [m for m, e in effort.items() if str(e).lower() == 'high']
    if len(high) > 12:
        tips.append(f'{len(high)} models set to high effort — trim unused entries to reduce settings noise.')
    if not tips:
        tips.append('No obvious tuning issues from heuristics; snapshot looks coherent.')
    return tips
