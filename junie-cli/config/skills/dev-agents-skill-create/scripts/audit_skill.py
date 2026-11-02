#!/usr/bin/env python3
"""
Audit an external/imported Agent Skill before it is installed into this repo.

Trust model (see SKILL.md "Trust Model" section): we trust only code we
wrote ourselves. Any skill that was not authored in this workflow — copied,
downloaded, or otherwise sourced externally (GitHub, ClawdHub, another
agent's export, etc.) — is untrusted, regardless of stars, author
reputation, or how official it looks. There is no tiered trust hierarchy
based on source; every imported skill goes through the exact same audit.

This script never installs, approves, or rejects a skill on its own — it
only produces AUDIT.md, a reviewable artifact that MUST be shown to the
user, who then interactively approves or rejects the import. Rejection
still requires archiving the skill to /tmp/ (via --archive-rejected)
instead of deleting it, in case the user wants to inspect it further.
"""

import argparse
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate import analyze_skill  # noqa: E402

THREAT_NOTES = {
    "Recursive deletion of root directory": "Destructive filesystem operation reaching outside the skill's own workspace.",
    "Piping curl output to bash": "Remote code execution — runs unreviewed remote content directly as shell code.",
    "Piping wget output to bash": "Remote code execution — runs unreviewed remote content directly as shell code.",
    "Setting overly permissive permissions": "Weakens filesystem permissions, widening the attack surface.",
    "Netcat reverse shell pattern": "Classic reverse-shell primitive; strongly indicates remote access intent.",
    "Direct TCP socket access": "Low-level network primitive that bypasses normal request tooling.",
    "Use of eval() in code": "Dynamic code execution; can run anything, including attacker-controlled input.",
    "Use of exec() in code": "Dynamic code execution; can run anything, including attacker-controlled input.",
    "Use of sudo commands": "Requests elevated privileges beyond the skill's own workspace.",
    "Privileged docker container": "Grants near-host-level access from inside a container.",
    "base64 decode of embedded payload": "Common technique to hide payloads or commands from casual review.",
    "Network call to raw IP address instead of a domain": "Bypasses domain-based review/allowlisting; common in exfiltration/C2 traffic.",
    "Possible browser cookie/session store access": "Targets stored session/login data, enabling account takeover.",
    "Accesses ~/.ssh (SSH keys)": "Targets SSH credentials used to access other systems.",
    "Accesses ~/.aws (cloud credentials)": "Targets cloud provider credentials.",
    "Accesses ~/.config directory": "Broad access to application configuration, which often holds secrets.",
    "Accesses .netrc credential file": "Targets stored plaintext network credentials.",
    "Accesses private key files": "Targets private key material directly.",
    "Accesses MEMORY.md": "Reads/writes agent memory — could exfiltrate or poison persistent agent state.",
    "Accesses SOUL.md": "Reads/writes core agent identity/behavior configuration.",
    "Accesses IDENTITY.md": "Reads/writes core agent identity/behavior configuration.",
    "Accesses USER.md": "Reads/writes stored user-specific data.",
}


def _threat_note_for(issue_text):
    for key, note in THREAT_NOTES.items():
        if key in issue_text:
            return note
    return "Flagged pattern; review manually to determine intent and impact."


def build_audit_report(data, source):
    """Render the AUDIT.md content (Markdown) from an analyze_skill() result dict."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    critical = data["critical_issues"]
    warnings = [i for i in data["all_issues"] if i.startswith("[WARNING]")]

    lines = []
    lines.append(f"# Audit Report: {data['name'] or '(unknown)'}")
    lines.append("")
    lines.append(f"- **Source (pre-install path):** `{source}`")
    lines.append(f"- **Audited at:** {now}")
    lines.append("- **Trust classification:** UNTRUSTED (not authored by this agent/workflow)")
    lines.append("")
    lines.append("## Threat Analysis")
    lines.append("")
    if critical:
        lines.append("| Finding | Location | Why it matters |")
        lines.append("|---|---|---|")
        for issue in critical:
            text = issue.replace("[CRITICAL] ", "")
            if " found in " in text:
                desc, loc = text.rsplit(" found in ", 1)
            else:
                desc, loc = text, "(unknown)"
            lines.append(f"| {desc} | `{loc}` | {_threat_note_for(desc)} |")
    else:
        lines.append("No critical red-flag patterns were detected by automated scanning.")
    lines.append("")
    if warnings:
        lines.append("**Warnings (non-critical, still review manually):**")
        for w in warnings:
            lines.append(f"- {w.replace('[WARNING] ', '')}")
        lines.append("")

    lines.append("## Code Analysis")
    lines.append("")
    lines.append(f"- **Files reviewed ({len(data['files_reviewed'])}):**")
    for f in data["files_reviewed"]:
        lines.append(f"  - `{f}`")
    lines.append(f"- **Executable files:** {', '.join(f'`{f}`' for f in data['executable_files']) or 'None'}")
    lines.append(f"- **Inline commands found in SKILL.md:** {len(data['command_lines'])}")
    for c in data["command_lines"][:20]:
        lines.append(f"  - `{c}`")
    if len(data["command_lines"]) > 20:
        lines.append(f"  - ... and {len(data['command_lines']) - 20} more")
    lines.append("")
    lines.append("## Permission Scope")
    lines.append("")
    lines.append(f"- **Network calls:** {', '.join(data['network_calls']) if data['network_calls'] else 'None'}")
    lines.append("")

    lines.append("## Risk Classification")
    lines.append("")
    lines.append(f"- **Risk level:** {data['risk_level']}")
    lines.append(f"- **Verdict:** {data['verdict']}")
    lines.append("")

    lines.append("## Validation Results")
    lines.append("")
    lines.append(f"- **Structural/naming validation:** {'PASS' if data['ok'] else 'FAIL'}")
    lines.append(f"- **Message:** {data['message']}")
    lines.append(f"- **Critical findings:** {len(critical)}")
    lines.append(f"- **Warnings:** {len(warnings)}")
    for agent, found in data["agent_docs"].items():
        lines.append(f"- **{agent} documentation present:** {'yes' if found else 'no'}")
    lines.append("")

    lines.append("## Required Next Steps")
    lines.append("")
    lines.append("1. Show this AUDIT.md to the user in full.")
    lines.append("2. Get explicit approve/reject decision from the user. If areas of concern remain,")
    lines.append("   start an interactive investigation of those specific files before deciding.")
    lines.append("3. If **rejected**: run `audit_skill.py <path> --archive-rejected` (do not install; do not delete).")
    lines.append("4. If **approved**: proceed to the mandatory final human review of the finished skill")
    lines.append("   (all files, not just the flagged ones) before it is copied into the skills directory.")
    lines.append("5. No skill — self-authored or imported — is installed without that final human sign-off.")
    lines.append("")

    return "\n".join(lines)


def write_audit(skill_path, output_path=None):
    skill_path = Path(skill_path)
    data = analyze_skill(skill_path)
    report = build_audit_report(data, source=str(skill_path.resolve()))
    out = Path(output_path) if output_path else (skill_path / "AUDIT.md")
    out.write_text(report)
    return data, out


def archive_rejected(skill_path, reason=None, archive_root="/tmp/rejected-skills"):
    """Move a rejected skill directory to /tmp/ (never delete it) so the user can revisit it later."""
    skill_path = Path(skill_path)
    if not skill_path.exists():
        raise FileNotFoundError(f"Path {skill_path} does not exist")

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    dest_root = Path(archive_root)
    dest_root.mkdir(parents=True, exist_ok=True)
    dest = dest_root / f"{skill_path.name}-{timestamp}"
    shutil.move(str(skill_path), str(dest))

    audit_path = dest / "AUDIT.md"
    rejection_note = f"\n## Rejection\n\n- **Rejected at:** {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}\n- **Reason:** {reason or '(not provided)'}\n- **Archived to:** `{dest}`\n"
    if audit_path.exists():
        with audit_path.open("a") as f:
            f.write(rejection_note)
    else:
        audit_path.write_text(f"# Audit Report: {skill_path.name}\n{rejection_note}")

    return dest


def main():
    parser = argparse.ArgumentParser(description="Audit an external skill and produce AUDIT.md before install.")
    parser.add_argument("skill_path", help="Path to the (not yet installed) skill directory to audit")
    parser.add_argument("--output", help="Where to write AUDIT.md (default: <skill_path>/AUDIT.md)")
    parser.add_argument("--archive-rejected", action="store_true",
                         help="Move the skill to /tmp/rejected-skills/ instead of installing it")
    parser.add_argument("--reason", help="Reason for rejection (used with --archive-rejected)")
    args = parser.parse_args()

    if args.archive_rejected:
        dest = archive_rejected(args.skill_path, reason=args.reason)
        print(f"[OK] Archived rejected skill to: {dest}")
        print("This skill was NOT installed. It remains available in /tmp/ for further review.")
        return

    data, out = write_audit(args.skill_path, args.output)
    print(f"[OK] Wrote audit report to: {out}")
    print(f"\nRisk level: {data['risk_level']}   Verdict: {data['verdict']}")
    print("\nNext: show this AUDIT.md to the user and obtain explicit approval before proceeding.")
    if data["risk_level"] == "EXTREME":
        sys.exit(1)


if __name__ == "__main__":
    main()
