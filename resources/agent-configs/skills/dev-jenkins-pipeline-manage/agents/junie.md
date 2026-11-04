# Junie specifics — dev-jenkins-pipeline-manage

## Context & Tuning
- Load the Jenkins reference only for pipeline, credential, agent, plugin, or controller concerns in scope.
- Keep secret use inside credential bindings and single-quoted shell steps.
- Treat fork contributions and agent/controller trust as security boundaries.
- Do not trigger production jobs, rotate credentials, or upgrade plugins without approval.
