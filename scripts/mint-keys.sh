#!/usr/bin/env bash
# Mint a GCP service account key for one lakehouse workload (or all four) and
# write it straight into the matching OCI Vault secret, gcp-key-<workload>.
# External Secrets then syncs it into the Kubernetes Secret of the same name.
# Rerun every 90 days to rotate.
#
# Usage: scripts/mint-keys.sh [options] <extractor|spark-drain|airflow|mcp-server|all>
#
# Options (each can also come from the environment variable shown):
#   --project ID            GCP project ID                      (GCP_PROJECT)
#   --vault-id OCID         OCI Vault OCID                      (OCI_VAULT_OCID)
#   --key-id OCID           OCI Vault master key OCID           (OCI_VAULT_KEY_OCID)
#   --compartment-id OCID   Compartment OCID holding the vault  (OCI_COMPARTMENT_OCID)
#   --keep-old-keys         Mint and store only; do not delete older keys
#   --prune-only            Mint nothing; delete every user-managed key except
#                           the one currently stored in the vault
#   --dry-run               Print what would happen and call no cloud API
#   -h, --help              Show this help
#
# The OCI CLI takes its region and profile from its own config or from
# OCI_CLI_REGION / OCI_CLI_PROFILE. gcloud uses the active account.
#
# Default flow per workload:
#   1. create a key for sa-<workload> and pipe it, in memory, into a new
#      version of the vault secret (the secret is created on first run);
#   2. read the stored key's ID back from the vault;
#   3. delete every other user-managed key of sa-<workload>.
# Long-running pods (Airflow, MCP server) keep using the old key until they
# restart. For a zero-downtime rotation run with --keep-old-keys, wait for the
# Kubernetes Secrets to sync and restart those pods, then run --prune-only.
#
# The key never touches disk, shell history, stdout/stderr or a process
# argument list: gcloud writes it to a pipe, jq wraps it in the request body
# in memory, and the OCI CLI reads that body from stdin.
set -euo pipefail
set +x
umask 077

readonly workloads=(extractor spark-drain airflow mcp-server)

usage() {
  sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
  echo "error: $*" >&2
  exit 2
}

project="${GCP_PROJECT:-}"
vault_id="${OCI_VAULT_OCID:-}"
key_id="${OCI_VAULT_KEY_OCID:-}"
compartment_id="${OCI_COMPARTMENT_OCID:-}"
mode="rotate"
dry_run=false
target=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project | --vault-id | --key-id | --compartment-id)
      [[ $# -ge 2 ]] || die "$1 needs a value"
      case "$1" in
        --project) project="$2" ;;
        --vault-id) vault_id="$2" ;;
        --key-id) key_id="$2" ;;
        --compartment-id) compartment_id="$2" ;;
      esac
      shift 2
      ;;
    --keep-old-keys)
      [[ "$mode" == "rotate" ]] || die "--keep-old-keys and --prune-only are mutually exclusive"
      mode="mint-only"
      shift
      ;;
    --prune-only)
      [[ "$mode" == "rotate" ]] || die "--keep-old-keys and --prune-only are mutually exclusive"
      mode="prune-only"
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      die "unknown option: $1 (see --help)"
      ;;
    *)
      [[ -z "$target" ]] || die "only one workload (or 'all') may be given"
      target="$1"
      shift
      ;;
  esac
done

[[ -n "$target" ]] || die "name a workload (${workloads[*]}) or 'all' (see --help)"

selected=()
if [[ "$target" == "all" ]]; then
  selected=("${workloads[@]}")
else
  for w in "${workloads[@]}"; do
    [[ "$w" == "$target" ]] && selected=("$w")
  done
  [[ ${#selected[@]} -eq 1 ]] || die "unknown workload '$target'; expected one of: ${workloads[*]} all"
fi

[[ -n "$project" ]] || die "set --project or GCP_PROJECT"
[[ "$project" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] || die "'$project' is not a valid GCP project ID"
[[ "$vault_id" =~ ^ocid1\.vault\. ]] || die "set --vault-id or OCI_VAULT_OCID to the vault OCID"
[[ "$compartment_id" =~ ^ocid1\.(compartment|tenancy)\. ]] || die "set --compartment-id or OCI_COMPARTMENT_OCID to the compartment OCID"
if [[ "$mode" != "prune-only" ]]; then
  [[ "$key_id" =~ ^ocid1\.key\. ]] || die "set --key-id or OCI_VAULT_KEY_OCID to the master key OCID"
fi

if [[ "$dry_run" == false ]]; then
  for tool in gcloud oci jq; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
  done
fi

log() {
  echo "[$1] $2"
}

# Prints the OCID of the ACTIVE vault secret with this name, or nothing.
find_secret_id() {
  oci vault secret list \
    --compartment-id "$compartment_id" \
    --vault-id "$vault_id" \
    --name "$1" \
    --lifecycle-state ACTIVE \
    --all \
    --query 'data[0].id' \
    --raw-output
}

# Creates a key for $1 (service account email) and stores it in vault secret
# $2. $3 is the existing secret OCID, or empty to create the secret. Prints the
# secret OCID. The key only ever flows through pipes; jq's stderr is dropped
# because a jq error message can quote its input.
mint_into_vault() {
  local sa_email="$1" secret_name="$2" secret_id="$3"
  local version_name
  version_name="minted-$(date -u +%Y%m%dT%H%M%SZ)"

  if [[ -z "$secret_id" ]]; then
    gcloud iam service-accounts keys create - \
      --iam-account="$sa_email" \
      --project="$project" \
      --quiet |
      jq -Rsc \
        --arg compartment "$compartment_id" \
        --arg vault "$vault_id" \
        --arg key "$key_id" \
        --arg name "$secret_name" \
        --arg version "$version_name" \
        'if (try (fromjson | .type == "service_account") catch false) then
           {compartmentId: $compartment, vaultId: $vault, keyId: $key,
            secretName: $name, secretContentName: $version,
            secretContentContent: @base64,
            description: "GCP service account key, written by scripts/mint-keys.sh",
            freeformTags: {Project: "SportsAgentic", ManagedBy: "mint-keys.sh"}}
         else error("not a service account key") end' 2>/dev/null |
      oci vault secret create-base64 \
        --from-json file:///dev/stdin \
        --wait-for-state ACTIVE \
        --query 'data.id' \
        --raw-output
  else
    gcloud iam service-accounts keys create - \
      --iam-account="$sa_email" \
      --project="$project" \
      --quiet |
      jq -Rsc \
        --arg secret "$secret_id" \
        --arg version "$version_name" \
        'if (try (fromjson | .type == "service_account") catch false) then
           {secretId: $secret, secretContentName: $version,
            secretContentContent: @base64}
         else error("not a service account key") end' 2>/dev/null |
      oci vault secret update-base64 \
        --from-json file:///dev/stdin \
        --wait-for-state ACTIVE \
        --query 'data.id' \
        --raw-output
  fi
}

# Prints the GCP key ID (private_key_id) of the key stored as the CURRENT
# version of vault secret $1. Only the ID leaves the pipe.
stored_key_id() {
  oci secrets secret-bundle get \
    --secret-id "$1" \
    --stage CURRENT \
    --query 'data."secret-bundle-content".content' \
    --raw-output |
    jq -Rr 'try (@base64d | fromjson | .private_key_id) catch empty' 2>/dev/null
}

# Deletes every user-managed key of $1 except key ID $2. Refuses to delete
# anything if $2 is not one of that account's keys.
prune_keys() {
  local sa_email="$1" keep="$2" existing kid deleted=0
  existing="$(gcloud iam service-accounts keys list \
    --iam-account="$sa_email" \
    --project="$project" \
    --managed-by=user \
    --format='value(name.basename())')"

  if ! grep -qx -- "$keep" <<<"$existing"; then
    echo "error: the key stored in the vault ($keep) is not a key of $sa_email; not deleting anything" >&2
    return 1
  fi

  while IFS= read -r kid; do
    [[ -n "$kid" && "$kid" != "$keep" ]] || continue
    gcloud iam service-accounts keys delete "$kid" \
      --iam-account="$sa_email" \
      --project="$project" \
      --quiet
    deleted=$((deleted + 1))
  done <<<"$existing"
  echo "deleted $deleted older key(s)"
}

for w in "${selected[@]}"; do
  sa_email="sa-${w}@${project}.iam.gserviceaccount.com"
  secret_name="gcp-key-${w}"

  if [[ "$dry_run" == true ]]; then
    if [[ "$mode" != "prune-only" ]]; then
      log "$w" "would create a new key for $sa_email"
      log "$w" "would write it to OCI Vault secret $secret_name (vault $vault_id, master key $key_id, compartment $compartment_id): create the secret if missing, otherwise add a new current version"
    fi
    if [[ "$mode" != "mint-only" ]]; then
      log "$w" "would read the stored key ID back from $secret_name and delete every other user-managed key of $sa_email"
    fi
    continue
  fi

  secret_id="$(find_secret_id "$secret_name")"

  if [[ "$mode" != "prune-only" ]]; then
    if [[ -z "$secret_id" ]]; then
      log "$w" "creating vault secret $secret_name with a new key for $sa_email"
    else
      log "$w" "adding a new version of vault secret $secret_name with a new key for $sa_email"
    fi
    secret_id="$(mint_into_vault "$sa_email" "$secret_name" "$secret_id")"
    [[ "$secret_id" =~ ^ocid1\.vaultsecret\. ]] || die "storing the key for $w failed; check the output above"
    log "$w" "stored in $secret_id"
  fi

  if [[ "$mode" == "mint-only" ]]; then
    log "$w" "keeping older keys (--keep-old-keys); run --prune-only after the pods pick up the new key"
    continue
  fi

  [[ -n "$secret_id" ]] || die "vault secret $secret_name does not exist; nothing to prune against"
  keep="$(stored_key_id "$secret_id")"
  [[ "$keep" =~ ^[0-9a-f]{40}$ ]] || die "could not read the stored key ID from $secret_name; not deleting any keys"
  log "$w" "vault holds key $keep; deleting the other user-managed keys of $sa_email"
  prune_keys "$sa_email" "$keep"
done

if [[ "$dry_run" == true ]]; then
  echo "dry run: nothing was changed"
fi
