# Claude Specifics for Dev Nginx Config Manage

## Context & Tuning
- Check directive names, contexts, defaults, and introduced-in versions against nginx.org module docs instead of recalling them.
- State `proxy_pass` URI and header-inheritance effects explicitly in explanations and PR notes.
- Distinguish NGINX Plus-only features (`keyval`, `api`, `sync`) from open-source equivalents before proposing them.

## Instructions Overrides
- Ask before production restarts/reloads or TLS policy changes.
- Never reveal private keys, htpasswd contents, or secret-bearing URLs.
