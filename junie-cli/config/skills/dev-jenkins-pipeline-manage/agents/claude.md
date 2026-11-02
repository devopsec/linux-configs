# Claude specifics — dev-jenkins-pipeline-manage

## Context & Tuning
- Read the applicable Jenkinsfile and shared-library context before proposing changes.
- Keep Groovy orchestration thin and avoid interpolating credentials into shell strings.
- Respect controller/agent separation and untrusted pull-request boundaries.
- Ask before changing production credentials, controller configuration, or plugin state.
