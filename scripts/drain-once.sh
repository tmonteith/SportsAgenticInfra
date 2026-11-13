#!/usr/bin/env bash
# Run the lakehouse streaming drain once: a one-off Spark Job in namespace data that drains
# Kafka (cfb.live_games, agent.events) into the bronze and silver Iceberg tables and exits.
# The Job is rendered from the local chart k8s/data/drain (template job.yaml) with the
# installed "ingest" release's values (OCIR registry and namespace, GCP project, Kafka
# bootstrap, pull secret), so it uses the same settings as the extractor and poller.
#
# Usage: scripts/drain-once.sh --tag TAG [--streams LIST] [--print] [--values FILE] [--context NAME]
#   --tag TAG       spark-drain image tag (short commit SHA pushed by the Lakehouse repo's drain-image.yml)
#   --streams LIST  comma list of live_game_events,agent_events (default: both, one after the other)
#   --print         print the Job manifest and stop; nothing is applied
#   --values FILE   render from FILE instead of reading the ingest release values (needs no cluster)
#   --context NAME  kubeconfig context to use (default: current context)
#
# Without --print the Job is created with `kubectl create`. Reruns are safe: the drain
# resumes from its checkpoints and an empty run writes nothing.

set -euo pipefail

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

namespace="data"
release="drain"
values_release="ingest"
chart_dir="$(cd "$(dirname "$0")/.." && pwd)/k8s/data/drain"

print_only=false
tag=""
streams=""
values_file=""
context=""

while [ $# -gt 0 ]; do
  case "$1" in
    --print) print_only=true; shift ;;
    --tag | --streams | --values | --context)
      [ $# -ge 2 ] || { echo "error: $1 needs a value" >&2; exit 2; }
      case "$1" in
        --tag) tag="$2" ;;
        --streams) streams="$2" ;;
        --values) values_file="$2" ;;
        --context) context="$2" ;;
      esac
      shift 2 ;;
    --tag=*) tag="${1#*=}"; shift ;;
    --streams=*) streams="${1#*=}"; shift ;;
    --values=*) values_file="${1#*=}"; shift ;;
    --context=*) context="${1#*=}"; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$tag" ]; then
  usage >&2
  exit 2
fi
if ! [[ "$tag" =~ ^[A-Za-z0-9._-]{1,128}$ ]]; then
  echo "error: invalid image tag: $tag" >&2
  exit 2
fi
if [ -n "$streams" ] && ! [[ "$streams" =~ ^(live_game_events|agent_events)(,(live_game_events|agent_events))*$ ]]; then
  echo "error: --streams must be a comma list of live_game_events and agent_events: $streams" >&2
  exit 2
fi

for tool in helm kubectl; do
  if [ "$tool" = kubectl ] && [ "$print_only" = true ]; then
    continue
  fi
  command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool is not installed" >&2; exit 2; }
done

# Context flags for each tool (helm and kubectl name it differently). Expanded with
# ${arr[@]+...} so empty arrays work under set -u on macOS bash 3.2.
helm_ctx=()
kubectl_ctx=()
if [ -n "$context" ]; then
  helm_ctx=(--kube-context "$context")
  kubectl_ctx=(--context "$context")
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ -z "$values_file" ]; then
  # Read-only: the values OpenTofu installed the ingest release with (no secrets in them).
  # The drain chart reads only image.registry, image.namespace, imagePullSecrets,
  # gcpProject and kafkaBootstrap from them; image.tag is replaced below.
  if ! helm get values "$values_release" --namespace "$namespace" --output yaml ${helm_ctx[@]+"${helm_ctx[@]}"} >"$tmp/release-values.yaml"; then
    echo "error: release $values_release not found in namespace $namespace; set ingest_image_tag and apply first, or pass --values" >&2
    exit 1
  fi
  values_file="$tmp/release-values.yaml"
fi

job_id="$(date -u +%Y%m%d%H%M%S)"
args="[]"
if [ -n "$streams" ]; then
  args="[\"--streams\", \"${streams}\"]"
fi

# A values file rather than --set: --set would split the comma-separated stream list.
# All values are validated above.
cat >"$tmp/drain-values.yaml" <<EOF_VALUES
image:
  tag: "${tag}"
drain:
  id: "${job_id}"
  args: ${args}
EOF_VALUES

helm template "$release" "$chart_dir" \
  --namespace "$namespace" \
  --values "$values_file" \
  --values "$tmp/drain-values.yaml" \
  --show-only templates/job.yaml >"$tmp/job.yaml"

if [ "$print_only" = true ]; then
  cat "$tmp/job.yaml"
  exit 0
fi

kubectl create --namespace "$namespace" ${kubectl_ctx[@]+"${kubectl_ctx[@]}"} -f "$tmp/job.yaml"
echo "Started job/spark-drain-${job_id} (image tag ${tag})."
echo "Follow it with: kubectl -n ${namespace} logs -f job/spark-drain-${job_id}"
echo "The last log line (drain_summary) has the per-stream batch, bronze, silver and reject counts."
