#!/usr/bin/env bash
# Backfill past CFB seasons into the lakehouse landing bucket with a one-off extractor
# Job in namespace data. The Job is rendered from the same chart as the nightly CronJob
# (k8s/data/ingest, template backfill-job.yaml) with the installed "ingest" release's
# values, so it uses the same image, project, key and limits.
#
# Usage: scripts/backfill.sh [--print] [--force] [--values FILE] [--context NAME] SEASON...
#   SEASON          a year (2024) or a range of years (2023-2025)
#   --print         print the Job manifest and stop; nothing is applied
#   --force         re-land responses that are already landed (new objects, never overwritten)
#   --values FILE   render from FILE instead of reading the release values (needs no cluster)
#   --context NAME  kubeconfig context to use (default: current context)
#
# Without --print the Job is created with `kubectl create`. Responses already landed are
# skipped, so rerunning a season costs one CFBD call (its calendar). One season is about
# 34 CFBD calls (calendar, teams, games and plays for every regular and postseason week).

set -euo pipefail

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

namespace="data"
release="ingest"
chart_dir="$(cd "$(dirname "$0")/.." && pwd)/k8s/data/ingest"

print_only=false
force=false
values_file=""
context=""
seasons=()

while [ $# -gt 0 ]; do
  case "$1" in
    --print) print_only=true; shift ;;
    --force) force=true; shift ;;
    --values)
      [ $# -ge 2 ] || { echo "error: $1 needs a value" >&2; exit 2; }
      values_file="$2"; shift 2 ;;
    --values=*) values_file="${1#*=}"; shift ;;
    --context)
      [ $# -ge 2 ] || { echo "error: $1 needs a value" >&2; exit 2; }
      context="$2"; shift 2 ;;
    --context=*) context="${1#*=}"; shift ;;
    -h | --help) usage; exit 0 ;;
    -*) echo "error: unknown option: $1" >&2; exit 2 ;;
    *)
      if ! [[ "$1" =~ ^[0-9]{4}(-[0-9]{4})?$ ]]; then
        echo "error: season must be a year or a range of years (2024, 2023-2025): $1" >&2
        exit 2
      fi
      seasons+=("$1"); shift ;;
  esac
done

if [ ${#seasons[@]} -eq 0 ]; then
  usage >&2
  exit 2
fi

for tool in helm kubectl; do
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
  # Read-only: the values OpenTofu installed the release with (no secrets in them).
  if ! helm get values "$release" --namespace "$namespace" --output yaml ${helm_ctx[@]+"${helm_ctx[@]}"} >"$tmp/release-values.yaml"; then
    echo "error: release $release not found in namespace $namespace; set ingest_image_tag and apply first" >&2
    exit 1
  fi
  values_file="$tmp/release-values.yaml"
fi

season_list="$(IFS=,; echo "${seasons[*]}")"
job_id="$(date -u +%Y%m%d%H%M%S)"
extra_args="[]"
if [ "$force" = true ]; then
  extra_args='["--force"]'
fi

# A values file rather than --set: --set would split the comma-separated season list.
# Both values are validated above (digits, "-" and ",").
cat >"$tmp/backfill-values.yaml" <<EOF_VALUES
backfill:
  enabled: true
  id: "${job_id}"
  seasons: "${season_list}"
  extraArgs: ${extra_args}
EOF_VALUES

helm template "$release" "$chart_dir" \
  --namespace "$namespace" \
  --values "$values_file" \
  --values "$tmp/backfill-values.yaml" \
  --show-only templates/backfill-job.yaml >"$tmp/job.yaml"

if [ "$print_only" = true ]; then
  cat "$tmp/job.yaml"
  exit 0
fi

kubectl create --namespace "$namespace" ${kubectl_ctx[@]+"${kubectl_ctx[@]}"} -f "$tmp/job.yaml"
echo "Started job/extractor-backfill-${job_id} for season(s) ${season_list}."
echo "Follow it with: kubectl -n ${namespace} logs -f job/extractor-backfill-${job_id}"
echo "The last log line (extractor_summary) has the landed, skipped and failed counts and the CFBD calls made."
