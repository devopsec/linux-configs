#!/usr/bin/env bash
# Read-only Kubernetes diagnostics (ported and merged from upstream
# cluster-health-check.sh + pod-debug.sh). Issues only get/describe/logs/top.

usage() {
  cat <<'EOF'
Usage: k8s-diagnose.sh cluster [namespace]
       k8s-diagnose.sh pod <pod-name> [namespace]
       k8s-diagnose.sh -h

Read-only: runs kubectl get/describe/logs/top/events against the CURRENT
kubeconfig context (printed first). Makes no changes to the cluster.

Env:
  LOG_TAIL   log lines per container (default 50)
  DEBUG=1    trace execution
EOF
}

set -Eeuo pipefail
shopt -s inherit_errexit nullglob
if [[ "${DEBUG:-0}" == 1 ]]; then set -x; fi

LOG_TAIL="${LOG_TAIL:-50}"

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
section() { printf '\n== %s ==\n' "$*"; }

require() {
  command -v kubectl &>/dev/null || { log 'missing dependency: kubectl'; exit 1; }
  [[ "$LOG_TAIL" =~ ^([1-9][0-9]{0,2}|1000)$ ]] || { log 'LOG_TAIL must be an integer from 1 to 1000'; exit 2; }
}

valid_namespace() {
  local name="$1"
  [[ ${#name} -le 63 && "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || {
    log "invalid namespace name: $name"
    exit 2
  }
}

valid_pod_name() {
  local name="$1"
  local label
  local IFS=.
  local -a labels=()

  [[ ${#name} -le 253 && "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$ ]] || {
    log "invalid pod name: $name"
    exit 2
  }

  read -r -a labels <<< "$name"
  for label in "${labels[@]}"; do
    (( ${#label} <= 63 )) || { log "invalid pod name label: $label"; exit 2; }
  done
}

print_context() {
  section "Context"
  kubectl config current-context || { log 'no current kubeconfig context'; exit 1; }
  kubectl version 2>/dev/null | sed -n '1,3p' || true
}

diag_cluster() {
  local ns="$1"
  local -a bad_nodes=() bad_pods=()

  section "Nodes"
  kubectl get nodes -o wide
  mapfile -t bad_nodes < <(kubectl get nodes --no-headers | awk '$2 !~ /^Ready/ {print $1}')
  (( ${#bad_nodes[@]} == 0 )) || log "WARNING: ${#bad_nodes[@]} node(s) not Ready: ${bad_nodes[*]}"

  section "Pods in namespace '$ns'"
  kubectl get pods -n "$ns" -o wide
  mapfile -t bad_pods < <(kubectl get pods -n "$ns" --no-headers \
    | awk '$3 ~ /Error|CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|OOMKilled|Pending/ {print $1 " (" $3 ")"}')
  (( ${#bad_pods[@]} == 0 )) || log "WARNING: ${#bad_pods[@]} pod(s) unhealthy: ${bad_pods[*]}"

  section "Workloads"
  kubectl get deploy,statefulset,daemonset -n "$ns" 2>/dev/null || true

  section "Resource usage"
  kubectl top nodes 2>/dev/null || echo "metrics-server not available"

  section "Recent warning events ($ns)"
  kubectl get events -n "$ns" --field-selector type=Warning --sort-by=.lastTimestamp 2>/dev/null | tail -n 20 || true

  section "PVCs / Services ($ns)"
  kubectl get pvc -n "$ns" 2>/dev/null || true
  kubectl get svc,endpointslices -n "$ns" 2>/dev/null || true
}

diag_pod() {
  local pod="$1" ns="$2" c
  local -a containers=()

  section "Pod $ns/$pod"
  kubectl get pod "$pod" -n "$ns" -o wide

  section "Describe"
  kubectl describe pod "$pod" -n "$ns"

  mapfile -t containers < <(kubectl get pod "$pod" -n "$ns" \
    -o jsonpath='{range .spec.initContainers[*]}{.name}{"\n"}{end}{range .spec.containers[*]}{.name}{"\n"}{end}')

  for c in "${containers[@]}"; do
    [[ -n "$c" ]] || continue
    section "Logs: $c (last $LOG_TAIL)"
    kubectl logs "$pod" -n "$ns" -c "$c" --tail="$LOG_TAIL" 2>/dev/null || echo "no logs"
    section "Previous logs: $c"
    kubectl logs "$pod" -n "$ns" -c "$c" --previous --tail="$LOG_TAIL" 2>/dev/null || echo "no previous container"
  done

  section "Resource usage"
  kubectl top pod "$pod" -n "$ns" --containers 2>/dev/null || echo "metrics not available"

  section "Events for pod"
  kubectl get events -n "$ns" --field-selector "involvedObject.name=$pod" --sort-by=.lastTimestamp || true
}

main() {
  local mode="${1:-}"

  case "$mode" in
    -h|--help) usage; exit 0 ;;
    cluster)
      (( $# <= 2 )) || { usage >&2; exit 2; }
      local ns="${2:-default}"
      require; valid_namespace "$ns"; print_context
      diag_cluster "$ns"
      ;;
    pod)
      (( $# >= 2 && $# <= 3 )) || { usage >&2; exit 2; }
      local pod="$2" ns="${3:-default}"
      require; valid_pod_name "$pod"; valid_namespace "$ns"; print_context
      diag_pod "$pod" "$ns"
      ;;
    *) usage >&2; exit 2 ;;
  esac
}

main "$@"
