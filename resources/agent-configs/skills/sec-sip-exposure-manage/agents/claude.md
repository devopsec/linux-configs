# Claude specifics — SIP/RTP perimeter

- Separate signalling, media, management, RPC, and database flows explicitly.
- Keep administration and control interfaces private and require a named owner for exceptions.
- Confirm RTP bounds against the running service configuration before rule changes.