# Junie specifics — GCP serverless

- Read the serverless config if present; do not create or modify config under the Junie home directory.
- Confirm ingress, runtime identity, and environment before deployment changes.
- Delegate event delivery semantics to the Pub/Sub skill rather than duplicating them.
