# Jenkins

Use an organization-approved Jenkins **LTS** and Java runtime, pinned in the host/image manifest and checked against Jenkins' compatibility matrix. Install from the signed distro repository (`pkg.jenkins.io`) or an approved image; do not pipe install scripts to a shell.

## Declarative Jenkinsfile (Python + uv)

```groovy
pipeline {
  agent { label 'linux' }
  options {
    timeout(time: 30, unit: 'MINUTES')
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '30'))
    timestamps()
  }
  environment {
    UV_CACHE_DIR = "${WORKSPACE}/.uv-cache"
  }
  stages {
    stage('Validate') {
      parallel {
        stage('Shell')  { steps { sh 'git ls-files -z "*.sh" | xargs -0 -r shellcheck -S error' } }
        stage('Python') {
          steps {
            sh '''
              set -euo pipefail
              uv lock --check
              uv sync --locked --all-packages
              uv run ty check src
              uv run pytest -q --junitxml=reports/junit.xml
            '''
          }
          post { always { junit allowEmptyResults: true, testResults: 'reports/*.xml' } }
        }
      }
    }
    stage('Publish') {
      when { branch 'main' }
      steps {
        withCredentials([file(credentialsId: 'gcp-publisher-wif-config', variable: 'GOOGLE_APPLICATION_CREDENTIALS')]) {
          sh './ci/publish.sh'          // single-quoted: secrets never interpolated by Groovy
        }
      }
    }
  }
  post {
    failure { echo "Failed: ${env.BUILD_URL}" }
    cleanup { cleanWs() }
  }
}
```

## Agents

| Agent | Use | Caution |
|---|---|---|
| `label 'linux'` | static VM agents | keep agents ephemeral where possible; no builds on the controller (`numExecutors 0`) |
| `docker { image '<approved-toolchain-image>@sha256:<digest>' }` | reproducible toolchain | record tool versions; do not mount docker.sock |
| `kubernetes { yaml ... }` | per-build pods on GKE | never `privileged: true` dind — build images with **kaniko**/**buildah** (rootless) instead |

## Credentials

```groovy
withCredentials([
  usernamePassword(credentialsId: 'registry', usernameVariable: 'REG_USER', passwordVariable: 'REG_PASS'),
  string(credentialsId: 'api-token', variable: 'API_TOKEN'),
  sshUserPrivateKey(credentialsId: 'deploy-key', keyFileVariable: 'SSH_KEY')
]) {
  sh 'printf "%s" "$REG_PASS" | docker login -u "$REG_USER" --password-stdin "$REGISTRY"'
}
withCredentials([gitUsernamePassword(credentialsId: 'github-app', gitToolName: 'Default')]) {
  sh 'git push origin HEAD:refs/heads/release'   // never embed tokens in the remote URL
}
```

- **Single-quote `sh` strings** that reference secrets; Groovy `"${SECRET}"` interpolation leaks the value into the process list and build log (Jenkins warns about it).
- Store credentials in Jenkins credential store backed by an external provider (GCP Secret Manager credentials provider plugin) — not in Jenkinsfiles or job config.
- Prefer GitHub App credentials over personal tokens.

## Parameters & reuse

```groovy
parameters {
  choice(name: 'ENV', choices: ['dev', 'stage', 'prod'], description: 'target')
  booleanParam(name: 'DRY_RUN', defaultValue: true)
}
```

Shared library (`vars/uvValidate.groovy` → `uvValidate()`), loaded with `@Library('ci-lib@<tag>') _` — pin to a tag, not a branch. Keep Groovy thin; put logic in versioned shell/Python scripts in the repo.

## Configuration as code

- JCasC (`jenkins.yaml`) for system config, credentials *references* (`${SECRET_NAME}` resolved from the secret source), security realm and authorization (Matrix / Role-based).
- Plugins pinned in `plugins.txt` and installed with `jenkins-plugin-cli --plugin-file plugins.txt`; review plugin security advisories before upgrades.
- Multibranch / organization folders discover `Jenkinsfile`s; restrict "trust" for fork PRs (`Trust: Nobody` or `From users with Admin or Write permission`).

## Hardening

- CSRF protection on, agent→controller security on, script approvals reviewed (no blanket approval of `Script Security` signatures).
- Controller behind SSO + TLS; no anonymous read.
- Run controller and agents as unprivileged users; isolate prod deploy credentials in a separate folder with restricted access.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `WorkflowScript: … expecting '}'` | `Pipeline Syntax` → declarative linter: `curl -X POST -F "jenkinsfile=<Jenkinsfile" "$JENKINS_URL/pipeline-model-converter/validate"` (authenticated) |
| Agent offline | agent JNLP/WebSocket connectivity, Java version mismatch, disk full |
| Controller OOM / slow | builds on controller, too many retained builds, heavy plugins; set `numExecutors 0`, log rotation |
| `Scripts not permitted to use method …` | move logic into a trusted shared library or a script file instead of approving broad signatures |
