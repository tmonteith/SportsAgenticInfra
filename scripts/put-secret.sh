#!/usr/bin/env bash
# Write one SportsAgentic secret value into the OCI Vault secret of the same
# name. External Secrets (ClusterSecretStore oci-vault) then syncs it into the
# Kubernetes Secret of that name. The first run creates the vault secret; later
# runs add a new current version.
#
# Usage: scripts/put-secret.sh [options] <cfbd-api-key|telemetry-salt|ocir-pull>
#
# Options (each can also come from the environment variable shown):
#   --vault-id OCID         OCI Vault OCID                      (OCI_VAULT_OCID)
#   --key-id OCID           OCI Vault master key OCID           (OCI_VAULT_KEY_OCID)
#   --compartment-id OCID   Compartment OCID holding the vault  (OCI_COMPARTMENT_OCID)
#   --dry-run               Read and check the value, print what would happen,
#                           call no cloud API
#   -h, --help              Show this help
#
# Secrets (only these names are accepted):
#   cfbd-api-key    namespace data,          data key CFBD_API_KEY
#                   the collegefootballdata.com API key, one line
#   telemetry-salt  namespace sportsagentic, data key TELEMETRY_SALT
#                   at least 32 characters, e.g. openssl rand -hex 32 | ...
#   ocir-pull       namespace data,          data key .dockerconfigjson
#                   a Docker config JSON with an "auths" object; must be piped
#                   in (see docs/secrets.md)
#
# The value comes from stdin: piped in, or typed twice at a hidden prompt when
# stdin is a terminal. Trailing newlines are dropped. It is never taken from
# the command line, echoed, or written to disk: printf (a shell builtin) pipes
# it to jq, which wraps it in the request body in memory, and the OCI CLI reads
# that body from stdin.
#
# The OCI CLI takes its region and profile from its own config or from
# OCI_CLI_REGION / OCI_CLI_PROFILE.
set -euo pipefail
set +x
umask 077

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

die() {
  echo "error: $*" >&2
  exit 2
}

vault_id="${OCI_VAULT_OCID:-}"
key_id="${OCI_VAULT_KEY_OCID:-}"
compartment_id="${OCI_COMPARTMENT_OCID:-}"
dry_run=false
name=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault-id | --key-id | --compartment-id)
      [[ $# -ge 2 ]] || die "$1 needs a value"
      case "$1" in
        --vault-id) vault_id="$2" ;;
        --key-id) key_id="$2" ;;
        --compartment-id) compartment_id="$2" ;;
      esac
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
    -*)
      die "unknown option: $1 (see --help)"
      ;;
    *)
      [[ -z "$name" ]] || die "only one secret name may be given"
      name="$1"
      shift
      ;;
  esac
done

# Allowlist: vault secret name = Kubernetes Secret name (amendment G3).
case "$name" in
  cfbd-api-key) namespace="data" data_key="CFBD_API_KEY" ;;
  telemetry-salt) namespace="sportsagentic" data_key="TELEMETRY_SALT" ;;
  ocir-pull) namespace="data" data_key=".dockerconfigjson" ;;
  "") die "name a secret: cfbd-api-key, telemetry-salt or ocir-pull (see --help)" ;;
  *) die "unknown secret '$name'; expected one of: cfbd-api-key telemetry-salt ocir-pull" ;;
esac

[[ "$vault_id" =~ ^ocid1\.vault\. ]] || die "set --vault-id or OCI_VAULT_OCID to the vault OCID"
[[ "$key_id" =~ ^ocid1\.key\. ]] || die "set --key-id or OCI_VAULT_KEY_OCID to the master key OCID"
[[ "$compartment_id" =~ ^ocid1\.(compartment|tenancy)\. ]] || die "set --compartment-id or OCI_COMPARTMENT_OCID to the compartment OCID"

tools=(jq)
[[ "$dry_run" == true ]] || tools+=(oci)
for tool in "${tools[@]}"; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed"
done

# 1. Read the value into memory only.
value=""
if [[ -t 0 ]]; then
  [[ "$name" != "ocir-pull" ]] || die "pipe the ocir-pull value in on stdin (see docs/secrets.md)"
  again=""
  IFS= read -rs -p "Value for $name (input hidden): " value
  echo >&2
  IFS= read -rs -p "Again, to confirm: " again
  echo >&2
  [[ "$value" == "$again" ]] || die "the two entries differ; nothing was written"
  unset again
else
  # Command substitution drops trailing newlines (e.g. from echo or openssl).
  value="$(cat)"
fi

# 2. Check it without ever printing it. jq's stderr is dropped because a jq
#    error message can quote its input.
[[ -n "$value" ]] || die "the value is empty; nothing was written"
case "$name" in
  cfbd-api-key)
    [[ "$value" =~ ^[^[:space:]]+$ ]] || die "the CFBD API key must be one word with no spaces or line breaks"
    ;;
  telemetry-salt)
    [[ "$value" =~ ^[^[:space:]]+$ ]] || die "the telemetry salt must have no spaces or line breaks"
    [[ ${#value} -ge 32 ]] || die "the telemetry salt must be at least 32 characters (try: openssl rand -hex 32 | $0 telemetry-salt)"
    ;;
  ocir-pull)
    printf '%s' "$value" |
      jq -e '(type == "object") and (.auths | type == "object") and (.auths | length > 0)' >/dev/null 2>&1 ||
      die "the ocir-pull value must be Docker config JSON with a non-empty \"auths\" object"
    if ! printf '%s' "$value" | jq -e '.auths | keys | any(test("ocir\\.io"))' >/dev/null 2>&1; then
      echo "warning: no OCIR registry (*.ocir.io) in \"auths\"; images in ord.ocir.io will not pull" >&2
    fi
    ;;
esac

# Prints the OCID of the ACTIVE vault secret with this name, or nothing.
# Same lookup as scripts/mint-keys.sh.
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

# Stores $value in vault secret $name. $1 is the existing secret OCID, or empty
# to create the secret. Prints the secret OCID.
write_value() {
  local secret_id="$1" version_name
  version_name="put-$(date -u +%Y%m%dT%H%M%SZ)"

  if [[ -z "$secret_id" ]]; then
    printf '%s' "$value" |
      jq -Rsc \
        --arg compartment "$compartment_id" \
        --arg vault "$vault_id" \
        --arg key "$key_id" \
        --arg name "$name" \
        --arg version "$version_name" \
        --arg description "Kubernetes Secret $name ($namespace, data key $data_key), written by scripts/put-secret.sh" \
        '{compartmentId: $compartment, vaultId: $vault, keyId: $key,
          secretName: $name, secretContentName: $version,
          secretContentContent: @base64,
          description: $description,
          freeformTags: {Project: "SportsAgentic", ManagedBy: "put-secret.sh"}}' 2>/dev/null |
      oci vault secret create-base64 \
        --from-json file:///dev/stdin \
        --wait-for-state ACTIVE \
        --query 'data.id' \
        --raw-output
  else
    printf '%s' "$value" |
      jq -Rsc \
        --arg secret "$secret_id" \
        --arg version "$version_name" \
        '{secretId: $secret, secretContentName: $version,
          secretContentContent: @base64}' 2>/dev/null |
      oci vault secret update-base64 \
        --from-json file:///dev/stdin \
        --wait-for-state ACTIVE \
        --query 'data.id' \
        --raw-output
  fi
}

if [[ "$dry_run" == true ]]; then
  echo "[$name] value read and checked (${#value} characters)"
  echo "[$name] would write it to OCI Vault secret $name (vault $vault_id, master key $key_id, compartment $compartment_id): create the secret if missing, otherwise add a new current version"
  echo "[$name] External Secrets would sync it into Secret $name in namespace $namespace, data key $data_key"
  echo "dry run: nothing was changed"
  exit 0
fi

# 3. Create the vault secret or add a new version.
secret_id="$(find_secret_id "$name")"
if [[ -z "$secret_id" ]]; then
  echo "[$name] creating vault secret $name"
else
  echo "[$name] adding a new version of vault secret $name"
fi
secret_id="$(write_value "$secret_id")"
unset value
[[ "$secret_id" =~ ^ocid1\.vaultsecret\. ]] || die "storing $name failed; check the output above"
echo "[$name] stored in $secret_id"
echo "[$name] External Secrets syncs it into Secret $name (namespace $namespace, data key $data_key) within the refresh interval (1h). To sync now:"
echo "  kubectl annotate externalsecret $name -n $namespace force-sync=\"\$(date +%s)\" --overwrite"
