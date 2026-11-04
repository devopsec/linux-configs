# Security & Audit Guidelines

Guidelines for security tasks, auditing agent workflows, and managing sensitive resources.

## Agent Workflow Auditing
- Use `agentmgr workflow audit latest` (`~/.junie/custom/bin/agentmgr`, add `--mermaid` for a graph) to monitor token usage, tool calls and the guideline interlock.
- Verify the **Interlock Rule** was followed: `REFERENCE` guidelines before task.
- Check for **SAD KITTI** JUMP/RET patterns in session events.

## General Security
- REFERENCE `~/.junie/custom/docs/general-guidelines.md` (Sections: "Credentials", "Code output standards")
- Secure coding: validate/normalize input at boundaries; no `eval`/`shell=True`/string-built SQL on untrusted data; least privilege for files (`0600` secrets), services and IAM; constant-time compares for tokens; redact secrets from logs and reports.
- Audit output: findings ordered by severity with file:line, impact, and a concrete remediation; no speculative findings without evidence.
- Credentials and keys MUST NOT leave the repository.
- Use `sectool` for infrastructure security audits.
- Explicitly announce `SKILL` usage via the "Skill Handshake".
