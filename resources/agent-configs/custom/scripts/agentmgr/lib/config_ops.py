"""Read/write Junie config.json and settings.json with safety guards."""

from __future__ import annotations

import json
import shutil
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .paths import JuniePaths, make_paths

# Keys that agentmgr may set without extra confirmation flags
CONFIG_SETTABLE = {
    'auto-update',
    'brave',
    'time-limit',
    'token-budget',
    'guidelines-location',
    'agent-default-location',
    'command-default-locations',
    'mcp-default-locations',
    'model-default-locations',
    'skill-default-locations',
    'flags',
    'provider',
}

SETTINGS_SETTABLE = {
    'ecoMode',
    'selectedTheme',
    'keepAwakeMode',
    'eventDensityMode',
    'shareAnonymousStatistics',
    'provider',
    'model',
    'modelForLaunch',
    'braveMode',
    'subagentsMode',
    'diffViewMode',
    'effortPerModel',
}

# Never auto-set these via agentmgr set without --force
PROTECTED_SETTINGS = {
    'sessionCount',
    'onboardingDefaultModelChosen',
    'steeringHintSeen',
    'tipsTaskCount',
    'defaultModelMigrationId',
}


def load_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding='utf-8'))


def dump_json(data: dict[str, Any]) -> str:
    return json.dumps(data, indent=2, ensure_ascii=False) + '\n'


def backup_file(path: Path, backup_dir: Path | None = None) -> Path | None:
    if not path.is_file():
        return None
    bdir = backup_dir or (path.parent / '.agentmgr-backups')
    bdir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    dest = bdir / f'{path.name}.{stamp}.bak'
    shutil.copy2(path, dest)
    return dest


def get_value(data: dict[str, Any], dotted_key: str) -> Any:
    cur: Any = data
    for part in dotted_key.split('.'):
        if not isinstance(cur, dict) or part not in cur:
            raise KeyError(dotted_key)
        cur = cur[part]
    return cur


def set_value(data: dict[str, Any], dotted_key: str, value: Any) -> dict[str, Any]:
    out = deepcopy(data)
    parts = dotted_key.split('.')
    cur = out
    for part in parts[:-1]:
        if part not in cur or not isinstance(cur[part], dict):
            cur[part] = {}
        cur = cur[part]
    cur[parts[-1]] = value
    return out


def coerce_value(raw: str) -> Any:
    """Parse CLI string into JSON-ish Python value."""
    s = raw.strip()
    low = s.lower()
    if low == 'true':
        return True
    if low == 'false':
        return False
    if low == 'null' or low == 'none':
        return None
    if (s.startswith('{') and s.endswith('}')) or (s.startswith('[') and s.endswith(']')):
        return json.loads(s)
    if (s.startswith('"') and s.endswith('"')) or (s.startswith("'") and s.endswith("'")):
        return s[1:-1]
    # int / float
    try:
        if '.' in s:
            return float(s)
        return int(s)
    except ValueError:
        return s


def show_config(paths: JuniePaths | None = None, which: str = 'both') -> dict[str, Any]:
    p = paths or make_paths()
    out: dict[str, Any] = {}
    if which in ('both', 'config'):
        out['config'] = load_json(p.config) if p.config.is_file() else {}
        out['config_path'] = str(p.config)
    if which in ('both', 'settings'):
        out['settings'] = load_json(p.settings) if p.settings.is_file() else {}
        out['settings_path'] = str(p.settings)
    return out


# Claude Code ~/.claude/settings.json keys agentmgr may write without --force.
CLAUDE_SETTINGS_SETTABLE = {
    'model',
    'modelSettings',
    'theme',
    'outputStyle',
    'permissions',
    'sandbox',
    'env',
    'hooks',
    'statusLine',
    'cleanupPeriodDays',
    'desktopSessionCleanupPeriodDays',
    'autoCompactEnabled',
    'autoUpdatesChannel',
    'minimumVersion',
    'preferredNotifChannel',
    'enableAllProjectMcpServers',
    'enabledMcpjsonServers',
    'disabledMcpjsonServers',
    'includeCoAuthoredBy',
    'alwaysThinkingEnabled',
    'spinnerTipsEnabled',
}
# Credential helpers and locally managed blocks: never written without --force.
CLAUDE_PROTECTED_SETTINGS = {
    'apiKeyHelper',
    'awsAuthRefresh',
    'awsCredentialExport',
    'gcpAuthRefresh',
    'forceLoginMethod',
    'forceLoginOrgUUID',
    'autoMode',
}


def apply_set(
    target: str,
    key: str,
    value: Any,
    paths: JuniePaths | None = None,
    *,
    dry_run: bool = True,
    force: bool = False,
    backup: bool = True,
) -> dict[str, Any]:
    """
    Set a config or settings key.
    target: 'config' | 'settings'
    """
    p = paths or make_paths()
    if target == 'config':
        path = p.config
        allowed = CONFIG_SETTABLE
        protected: set[str] = set()
    elif target == 'settings':
        path = p.settings
        if getattr(p, 'agent', 'junie') == 'claude':
            allowed = CLAUDE_SETTINGS_SETTABLE
            protected = CLAUDE_PROTECTED_SETTINGS
        else:
            allowed = SETTINGS_SETTABLE
            protected = PROTECTED_SETTINGS
    else:
        raise ValueError(f'unknown target: {target}')

    top = key.split('.', 1)[0]
    if top in protected and not force:
        raise PermissionError(f'refusing to set protected settings key {top!r} without --force')
    if top not in allowed and not force:
        raise PermissionError(
            f'key {top!r} not in allow-list for {target}; pass --force to override'
        )

    current = load_json(path) if path.is_file() else {}
    old = None
    try:
        old = get_value(current, key)
    except KeyError:
        old = None
    updated = set_value(current, key, value)
    result = {
        'target': target,
        'path': str(path),
        'key': key,
        'old': old,
        'new': value,
        'dry_run': dry_run,
        'backup': None,
        'wrote': False,
    }
    if dry_run:
        return result
    if backup and path.is_file():
        result['backup'] = str(backup_file(path))
    path.write_text(dump_json(updated), encoding='utf-8')
    result['wrote'] = True
    return result
