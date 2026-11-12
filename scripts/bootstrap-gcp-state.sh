#!/usr/bin/env bash
# One-time bootstrap for the gcp/ OpenTofu stack. Safe to rerun.
#
#   1. Enables the APIs OpenTofu needs before its first plan (Service Usage to
#      enable the rest, Resource Manager and Cloud Billing for the stack's data
#      sources, Cloud Storage for the state bucket).
#   2. Creates the remote state bucket <project>-sa-tfstate in us-central1:
#      single region, versioning on, uniform bucket-level access, public access
#      prevention enforced. It is never force-destroyed; delete it by hand.
#
# Usage: scripts/bootstrap-gcp-state.sh [--project PROJECT_ID] [--dry-run]
#        (or set GCP_PROJECT)
set -euo pipefail

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

project="${GCP_PROJECT:-}"
dry_run=false
readonly region="us-central1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || { echo "error: --project needs a value" >&2; exit 2; }
      project="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=true
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

if [[ -z "$project" ]]; then
  echo "error: set --project or GCP_PROJECT" >&2
  exit 2
fi
if [[ ! "$project" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
  echo "error: '$project' is not a valid GCP project ID" >&2
  exit 2
fi

readonly bucket="gs://${project}-sa-tfstate"
readonly apis=(
  serviceusage.googleapis.com
  cloudresourcemanager.googleapis.com
  cloudbilling.googleapis.com
  storage.googleapis.com
)

run() {
  echo "+ $*"
  if [[ "$dry_run" == false ]]; then
    "$@"
  fi
}

command -v gcloud >/dev/null 2>&1 || { echo "error: gcloud is not installed" >&2; exit 1; }

echo "Project: ${project}"
echo "State bucket: ${bucket} (${region})"

run gcloud services enable "${apis[@]}" --project="$project"

if [[ "$dry_run" == false ]] && gcloud storage buckets describe "$bucket" --project="$project" --format='value(name)' >/dev/null 2>&1; then
  echo "State bucket already exists; enforcing its settings."
else
  run gcloud storage buckets create "$bucket" \
    --project="$project" \
    --location="$region" \
    --default-storage-class=STANDARD \
    --uniform-bucket-level-access \
    --public-access-prevention
fi

# Rerunning this enforces the settings on a bucket that already exists.
run gcloud storage buckets update "$bucket" \
  --project="$project" \
  --versioning \
  --uniform-bucket-level-access \
  --public-access-prevention

echo "Done. Next: cd gcp && tofu init && tofu plan"
