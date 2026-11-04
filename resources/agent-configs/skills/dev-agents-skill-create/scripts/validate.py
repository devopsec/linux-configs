#!/usr/bin/env python3
"""
Validation script for Agent Skills.
Thoroughly checks for safety, naming conventions, and agent standards.
"""

import re
import sys
from pathlib import Path
import yaml

MAX_SKILL_NAME_LENGTH = 64

# Always CRITICAL when matched (true destructive / reverse-shell class).
DANGEROUS_PATTERNS = [
    # Root wipe only: `rm -rf /`, `rm -rf /*`, `rm -rf "/"` — NOT `/tmp`, `/var/tmp`, `$HOME/...`.
    (
        r'''rm\s+-rf\s+(?:/(?:\s|\*|$)|["']/(?:["']|\*))''',
        "Recursive deletion of filesystem root",
    ),
    (r"chmod\s+777", "Setting overly permissive permissions"),
    (r"nc\s+.*-e", "Netcat reverse shell pattern"),
    (r">\s*/dev/tcp", "Direct TCP socket access"),
    (r"docker\s+run\s+--privileged", "Privileged docker container"),
    (r"base64\s+(-d|--decode)", "base64 decode of embedded payload"),
    (r"https?://\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}", "Network call to raw IP address instead of a domain"),
    (r"(?i)(cookies?\.sqlite|cookies?\.db|Login Data)", "Possible browser cookie/session store access"),
]

# CRITICAL in executable scripts/; WARNING in SKILL.md / references/ (docs often show install or anti-patterns).
CONTEXTUAL_DANGEROUS_PATTERNS = [
    (r"curl\s+.*\s*\|\s*bash", "Piping curl output to bash"),
    (r"wget\s+.*\s*\|\s*bash", "Piping wget output to bash"),
    (r"eval\(", "Use of eval() in code"),
    (r"exec\(", "Use of exec() in code"),
    (r"sudo\s+", "Use of sudo commands"),
]

CREDENTIAL_PATTERNS = [
    (r"(?i)api[_-]?key", "Possible API Key"),
    (r"(?i)token", "Possible Token"),
    (r"(?i)password", "Possible Password"),
    (r"(?i)secret", "Possible Secret"),
]

# Credential / config directories that should not be touched without clear justification
CREDENTIAL_FILE_PATTERNS = [
    (r"~/\.ssh", "Accesses ~/.ssh (SSH keys)"),
    (r"~/\.aws", "Accesses ~/.aws (cloud credentials)"),
    (r"~/\.config", "Accesses ~/.config directory"),
    (r"(?i)\.netrc", "Accesses .netrc credential file"),
    (r"id_rsa|id_ed25519", "Accesses private key files"),
]

# Agent identity / memory files that should not be read or modified by a skill
IDENTITY_FILE_PATTERNS = [
    (r"(?i)\bMEMORY\.md\b", "Accesses MEMORY.md"),
    (r"(?i)\bSOUL\.md\b", "Accesses SOUL.md"),
    (r"(?i)\bIDENTITY\.md\b", "Accesses IDENTITY.md"),
    (r"(?i)\bUSER\.md\b", "Accesses USER.md"),
]

# Patterns used to surface network/permission scope in the report (informational, not necessarily critical)
NETWORK_PATTERNS = [
    r"curl\s+[^\n|]*",
    r"wget\s+[^\n|]*",
    r"https?://[^\s\"'`]+",
]

def _is_script_path(file_path: str) -> bool:
    """True for skill scripts/ (executable logic); False for narrative SKILL.md / references."""
    norm = file_path.replace("\\", "/")
    return "/scripts/" in f"/{norm}" or norm.startswith("scripts/")


def check_file_content(file_path, content):
    issues = []

    # Always-critical dangerous patterns
    for pattern, description in DANGEROUS_PATTERNS:
        if re.search(pattern, content):
            issues.append(f"[CRITICAL] {description} found in {file_path}")

    # Context-sensitive: real risk in scripts; documentation often quotes installers / anti-patterns
    for pattern, description in CONTEXTUAL_DANGEROUS_PATTERNS:
        if re.search(pattern, content):
            level = "CRITICAL" if _is_script_path(file_path) else "WARNING"
            issues.append(f"[{level}] {description} found in {file_path}")

    # Credential patterns (mostly as warnings)
    for pattern, description in CREDENTIAL_PATTERNS:
        matches = re.findall(pattern, content)
        if matches:
            issues.append(f"[WARNING] Potential hardcoded credential '{matches[0]}' detected in {file_path}.")
            break

    # Credential / config file access:
    # Narrative SKILL.md/references often document where tools look (~/.aws, ~/.ssh, ~/.config).
    # Treat those as WARNING in docs; keep CRITICAL inside scripts/ (code that touches them).
    for pattern, description in CREDENTIAL_FILE_PATTERNS:
        if re.search(pattern, content):
            level = "CRITICAL" if _is_script_path(file_path) else "WARNING"
            issues.append(f"[{level}] {description} found in {file_path}")

    # Agent identity/memory file names in docs (e.g. Junie CLI explaining MEMORY.md) → WARNING;
    # scripts that read/write them → CRITICAL.
    for pattern, description in IDENTITY_FILE_PATTERNS:
        if re.search(pattern, content):
            level = "CRITICAL" if _is_script_path(file_path) else "WARNING"
            issues.append(f"[{level}] {description} found in {file_path}")

    return issues

def extract_permission_scope(file_path, content):
    """Extract network calls for the permission-scope section of the report."""
    network_calls = []
    for pattern in NETWORK_PATTERNS:
        for match in re.findall(pattern, content):
            network_calls.append(f"{file_path}: {match.strip()}")
    return network_calls

def classify_risk(all_issues, network_calls):
    """Classify overall risk level based on collected findings.

    This is purely a function of what was actually found in the skill's own
    files (dangerous patterns, credential/identity access, network scope).
    It does NOT factor in source reputation, popularity, or author trust —
    see the "Trust Model" section in SKILL.md: we trust code we wrote
    ourselves, and nothing else, regardless of where it came from.
    """
    critical_text = " ".join(i for i in all_issues if i.startswith("[CRITICAL]"))

    extreme_markers = ["filesystem root", "root directory", "privileged docker", "overly permissive permissions", "Direct TCP socket", "Netcat reverse shell"]
    high_markers = ["~/.ssh", "~/.aws", ".netrc", "private key", "sudo", "MEMORY.md", "SOUL.md", "IDENTITY.md", "USER.md", "eval()", "exec()"]

    if any(marker in critical_text for marker in extreme_markers):
        return "EXTREME"
    if any(marker in critical_text for marker in high_markers):
        return "HIGH"
    if network_calls or any(i.startswith("[CRITICAL]") for i in all_issues):
        return "MEDIUM"
    return "LOW"

def analyze_skill(skill_path):
    """Gather all structural, safety, and risk-classification data for a skill.

    Pure data-collection: never prints anything. Returns a dict so both the
    CLI validator (below) and scripts/audit_skill.py (AUDIT.md generator for
    imported/external skills) share a single source of truth and can never
    drift apart.
    """
    skill_path = Path(skill_path)
    result = {
        "path": str(skill_path),
        "ok": False,
        "message": "",
        "name": None,
        "frontmatter": None,
        "files_reviewed": [],
        "all_issues": [],
        "critical_issues": [],
        "network_calls": [],
        "command_lines": [],
        "executable_files": [],
        "risk_level": None,
        "verdict": None,
        "agent_docs": {},
        "openai_violation": False,
    }

    if not skill_path.exists():
        result["message"] = f"Path {skill_path} does not exist"
        return result

    skill_md = skill_path / "SKILL.md"
    if not skill_md.exists():
        result["message"] = "SKILL.md not found"
        return result

    content = skill_md.read_text()
    if not content.startswith("---"):
        result["message"] = "No YAML frontmatter found in SKILL.md"
        return result

    match = re.match(r"^---\n(.*?)\n---", content, re.DOTALL)
    if not match:
        result["message"] = "Invalid frontmatter format in SKILL.md"
        return result

    try:
        frontmatter = yaml.safe_load(match.group(1))
    except yaml.YAMLError as e:
        result["message"] = f"Invalid YAML in frontmatter: {e}"
        return result

    if "name" not in frontmatter or "description" not in frontmatter:
        result["message"] = "Missing 'name' or 'description' in frontmatter"
        return result
    result["frontmatter"] = frontmatter

    name = frontmatter.get("name", "").strip()
    result["name"] = name
    # Hyphen-separated segments; segments may use camelCase (bestPractices, mcpServer, fixIssue).
    if not re.match(r"^[a-z][a-zA-Z0-9]*(-[a-zA-Z0-9]+)+$", name) and not re.match(
        r"^[a-z][a-zA-Z0-9]*$", name
    ):
        result["message"] = (
            f"Name '{name}' should be hyphen-separated segments "
            f"(optional camelCase within a segment, e.g. docs-web-bestPractices-read)."
        )
        return result

    all_issues = []
    executable_files = []
    command_lines = []
    network_calls = []
    files_reviewed = ["SKILL.md"]

    # Check SKILL.md for inline commands
    all_issues.extend(check_file_content("SKILL.md", content))
    network_calls.extend(extract_permission_scope("SKILL.md", content))
    # Extract code blocks that look like bash
    bash_blocks = re.findall(r"```(?:bash|sh|shell)\n(.*?)\n```", content, re.DOTALL)
    for block in bash_blocks:
        for line in block.splitlines():
            if line.strip() and not line.strip().startswith("#"):
                command_lines.append(f"SKILL.md: {line.strip()}")

    # Check scripts directory
    # Note: this validator's own source (validate.py) and the audit-report generator
    # (audit_skill.py) are excluded — they necessarily contain the red-flag strings/
    # markers as literals (patterns + threat-note descriptions) to detect and explain
    # them, which would otherwise self-trigger false positives.
    SELF_EXCLUDED_SCRIPTS = {"validate.py", "audit_skill.py"}
    scripts_dir = skill_path / "scripts"
    if scripts_dir.exists():
        for f in scripts_dir.rglob("*"):
            if f.is_file():
                # Skip Python bytecode caches: not reviewable source, and can
                # contain compiled string literals that false-trigger patterns.
                if "__pycache__" in f.parts or f.suffix == ".pyc":
                    continue
                rel_path = str(f.relative_to(skill_path))
                executable_files.append(rel_path)
                files_reviewed.append(rel_path)
                if f.name in SELF_EXCLUDED_SCRIPTS:
                    continue
                try:
                    f_content = f.read_text(errors='ignore')
                    all_issues.extend(check_file_content(rel_path, f_content))
                    network_calls.extend(extract_permission_scope(rel_path, f_content))
                except Exception as e:
                    all_issues.append(f"[WARNING] Could not read {f}: {e}")

    # Check references directory
    refs_dir = skill_path / "references"
    if refs_dir.exists():
        for f in refs_dir.rglob("*.md"):
            if f.is_file():
                rel_path = str(f.relative_to(skill_path))
                files_reviewed.append(rel_path)
                try:
                    f_content = f.read_text()
                    all_issues.extend(check_file_content(rel_path, f_content))
                    network_calls.extend(extract_permission_scope(rel_path, f_content))
                except Exception as e:
                    all_issues.append(f"[WARNING] Could not read {f}: {e}")

    risk_level = classify_risk(all_issues, network_calls)
    critical_issues = [i for i in all_issues if i.startswith("[CRITICAL]")]

    if risk_level == "EXTREME":
        verdict = "DO NOT INSTALL"
    elif risk_level == "HIGH":
        verdict = "HUMAN APPROVAL REQUIRED"
    elif risk_level == "MEDIUM":
        verdict = "FULL REVIEW REQUIRED"
    else:
        verdict = "OK"

    agent_docs = {}
    for agent in ("junie", "claude"):
        md_paths = [
            skill_path / "agents" / f"{agent}.md",
            skill_path / "references" / f"{agent}.md",
        ]
        agent_docs[agent] = any(p.exists() for p in md_paths)

    openai_violation = (skill_path / "agents" / "openai.yaml").exists() or (skill_path / "agents" / "openai.md").exists()

    result.update({
        "files_reviewed": files_reviewed,
        "all_issues": all_issues,
        "critical_issues": critical_issues,
        "network_calls": network_calls,
        "command_lines": command_lines,
        "executable_files": executable_files,
        "risk_level": risk_level,
        "verdict": verdict,
        "agent_docs": agent_docs,
        "openai_violation": openai_violation,
    })

    if openai_violation:
        result["message"] = "OpenAI references are not allowed in this repo."
        return result

    if critical_issues:
        result["message"] = "Skill failed critical safety checks."
        return result

    if risk_level == "EXTREME":
        result["message"] = "Skill classified as EXTREME risk. Do not install."
        return result

    result["ok"] = True
    result["message"] = "Skill validation completed successfully."
    return result

def validate_skill(skill_path):
    """CLI-facing entry point: runs analyze_skill() and prints a human-readable report."""
    skill_path = Path(skill_path)
    print(f"\n=== Validating Skill: {skill_path.name} ===")

    print("[1/6] Checking file structure...")
    print("[2/6] Checking SKILL.md metadata...")
    print("[3/6] Checking naming convention...")
    print("[4/6] Running safety & security checks...")

    data = analyze_skill(skill_path)

    # Bail out early if we couldn't even get through structural/metadata/naming checks
    # (in those cases analyze_skill() returns before risk_level is ever computed)
    if data["risk_level"] is None:
        return False, data["message"]

    for issue in data["all_issues"]:
        print(issue)

    if data["command_lines"] or data["executable_files"]:
        print("\n[!] ATTENTION: This skill contains executable code or commands.")
        if data["command_lines"]:
            print("\nFound the following commands in SKILL.md:")
            for cmd in data["command_lines"][:10]:
                print(f"  > {cmd}")
            if len(data["command_lines"]) > 10:
                print(f"  ... and {len(data['command_lines']) - 10} more.")

        if data["executable_files"]:
            print("\nFound executable files:")
            for f in data["executable_files"]:
                print(f"  - {f}")

        print("\nSAFETY REQUIREMENT:")
        print("1. As an agent, you MUST thoroughly review these commands with the user.")
        print("2. Do NOT execute any of these without explicit user confirmation.")
        print("3. Check for any side effects or external network calls.")

    print("\n[5/6] Computing risk classification...")
    print("\nSKILL VETTING REPORT")
    print("=" * 50)
    print(f"Skill: {data['name']}")
    print(f"Files Reviewed: {len(data['files_reviewed'])}")
    print("-" * 50)
    print(f"RED FLAGS: {'None' if not data['critical_issues'] else len(data['critical_issues'])}")
    print("PERMISSIONS NEEDED:")
    print(f"  Network: {data['network_calls'] if data['network_calls'] else 'None'}")
    print(f"  Commands: {data['command_lines'] if data['command_lines'] else 'None'}")
    print("-" * 50)
    print(f"RISK LEVEL: {data['risk_level']}")
    print(f"VERDICT: {data['verdict']}")
    print("=" * 50)

    print("\n[6/6] Checking agent-specific documentation...")
    for agent, found in data["agent_docs"].items():
        if found:
            print(f"[OK] Found {agent}-specific documentation.")
        else:
            print(f"[WARNING] Missing {agent}-specific documentation (e.g., agents/{agent}.md).")

    if data["openai_violation"]:
        print("[CRITICAL] OpenAI-specific configuration found. Please remove OpenAI references.")

    return data["ok"], data["message"]

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python validate.py <skill_directory>")
        sys.exit(1)

    success, message = validate_skill(sys.argv[1])
    print(f"\nResult: {message}")
    sys.exit(0 if success else 1)
