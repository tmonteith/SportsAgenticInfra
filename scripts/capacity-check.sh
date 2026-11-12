#!/usr/bin/env bash
# Capacity check for the OKE cluster: per node, allocatable memory and CPU versus the sum
# of pod requests, and the headroom left. Read-only (kubectl get only).
#
# Exits 1 when any node's memory headroom is below the threshold (default 1.5 GiB, the
# lakehouse plan's gate), 2 on usage or tool errors.
#
# Usage: scripts/capacity-check.sh [--min-memory-headroom QUANTITY] [--context NAME]
#   --min-memory-headroom  Kubernetes quantity, e.g. 1536Mi, 1.5Gi, 2G (default 1536Mi)
#   --context              kubeconfig context to use (default: current context)
#
# Requests are counted the way the scheduler counts them: the larger of (sum of app
# containers + sidecar init containers) and (largest regular init container), plus pod
# overhead. Pods that have finished (Succeeded or Failed) are ignored.

set -euo pipefail

threshold="1536Mi"
kubectl_args=()

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --min-memory-headroom)
      [ $# -ge 2 ] || { echo "error: $1 needs a value" >&2; exit 2; }
      threshold="$2"
      shift 2
      ;;
    --min-memory-headroom=*)
      threshold="${1#*=}"
      shift
      ;;
    --context)
      [ $# -ge 2 ] || { echo "error: $1 needs a value" >&2; exit 2; }
      kubectl_args+=(--context "$2")
      shift 2
      ;;
    --context=*)
      kubectl_args+=(--context "${1#*=}")
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

for tool in kubectl jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool is required" >&2; exit 2; }
done

nodes_json="$(kubectl "${kubectl_args[@]+"${kubectl_args[@]}"}" get nodes -o json)"
pods_json="$(kubectl "${kubectl_args[@]+"${kubectl_args[@]}"}" get pods --all-namespaces -o json \
  --field-selector=status.phase!=Succeeded,status.phase!=Failed)"

report="$(jq -n -r \
  --argjson nodes "$nodes_json" \
  --argjson pods "$pods_json" \
  --arg threshold "$threshold" '
  # Kubernetes quantity -> bytes (memory) or millicores (cpu).
  def bytes:
    if . == null then 0
    else tostring
      | capture("^(?<n>[0-9.]+(e[0-9]+)?)(?<u>[A-Za-z]*)$")
      | (.n | tonumber) * ({
          "": 1, "k": 1e3, "K": 1e3, "M": 1e6, "G": 1e9, "T": 1e12,
          "Ki": 1024, "Mi": 1048576, "Gi": 1073741824, "Ti": 1099511627776,
          "m": 0.001
        }[.u] // error("unknown memory unit: \(.u)"))
    end;
  def millis:
    if . == null then 0
    else tostring
      | if endswith("m") then (.[:-1] | tonumber) else (tonumber * 1000) end
    end;
  def mib: . / 1048576 | floor;

  # Effective request of one pod for resource r ("memory" or "cpu").
  def pod_request(r; conv):
    ([.spec.containers[]? | .resources.requests[r] | conv] | add // 0) as $app
    | ([.spec.initContainers[]? | select(.restartPolicy == "Always") | .resources.requests[r] | conv] | add // 0) as $sidecars
    | ([.spec.initContainers[]? | select(.restartPolicy != "Always") | .resources.requests[r] | conv] | max // 0) as $init
    | ((.spec.overhead // {})[r] | conv) as $overhead
    | ([$app + $sidecars, $init] | max) + $overhead;

  ($threshold | bytes) as $min_headroom
  | [ $nodes.items[] | .metadata.name as $node
      | [ $pods.items[] | select(.spec.nodeName == $node) ] as $node_pods
      | {
          node: $node,
          pods: ($node_pods | length),
          mem_alloc: (.status.allocatable.memory | bytes),
          mem_req: ([ $node_pods[] | pod_request("memory"; bytes) ] | add // 0),
          cpu_alloc: (.status.allocatable.cpu | millis),
          cpu_req: ([ $node_pods[] | pod_request("cpu"; millis) ] | add // 0)
        }
      | .mem_free = (.mem_alloc - .mem_req)
      | .cpu_free = (.cpu_alloc - .cpu_req)
      | .ok = (.mem_free >= $min_headroom)
    ] as $rows
  | ([ $pods.items[] | select(.spec.nodeName == null) ] | length) as $unscheduled
  | (
      ["NODE", "PODS", "MEM_ALLOCATABLE", "MEM_REQUESTED", "MEM_HEADROOM", "CPU_ALLOCATABLE", "CPU_REQUESTED", "CPU_HEADROOM", "MEMORY_CHECK"],
      ( $rows[] | [
          .node, (.pods | tostring),
          "\(.mem_alloc | mib)Mi", "\(.mem_req | mib)Mi", "\(.mem_free | mib)Mi",
          "\(.cpu_alloc | floor)m", "\(.cpu_req | floor)m", "\(.cpu_free | floor)m",
          (if .ok then "ok" else "LOW" end)
        ] )
    | @tsv
    ),
    "",
    "Memory headroom threshold: \($min_headroom | mib)Mi (requests only; limits and actual use are not counted).",
    (if $unscheduled > 0 then "WARNING: \($unscheduled) pod(s) have no node yet (Pending); their requests are not counted above." else empty end),
    (if ($rows | length) == 0 then "RESULT: no nodes found"
     elif all($rows[]; .ok) then "RESULT: ok"
     else "RESULT: memory headroom below threshold on: \([ $rows[] | select(.ok | not) | .node ] | join(", "))" end)
')"

tab="$(printf '\t')"
table="$(printf '%s\n' "$report" | grep "$tab" || true)"
if command -v column >/dev/null 2>&1; then
  printf '%s\n' "$table" | column -t -s "$tab"
else
  printf '%s\n' "$table"
fi
echo
printf '%s\n' "$report" | grep -v "$tab" | grep -v '^$' || true

if printf '%s\n' "$report" | tail -n 1 | grep -q '^RESULT: ok$'; then
  exit 0
fi
exit 1
