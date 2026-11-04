# Claude specifics — sec-container-runtime-harden

## Context & Tuning
- Resolve the tool and threshold from config or the skill's explicit defaults before scanning.
- Focus findings on concrete image/runtime controls and preserve platform security profiles.
- Route Kubernetes admission/cluster policy work to the dedicated Kubernetes hardening skill.
- Do not disclose secrets or approve exceptions without an owner and expiry.
