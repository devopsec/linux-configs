# Junie specifics — sec-llm-api-harden

- Map authentication, provider, logging, and retention boundaries before changing operational controls.
- Never print provider credentials or raw prompts; use secret-manager references and redacted events.
- No commits; show proposed API, quota, or retention changes as a reviewable diff.
