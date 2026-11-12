# Secrets on OKE: OCI Vault and External Secrets

Each OKE workload that calls GCP has its own service account key. The key goes from GCP into OCI
Vault and from there into a Kubernetes Secret. It never passes through Git, OpenTofu state,
container images, CI logs or chat. Three other secrets (the CFBD API key, the telemetry salt and
the OCIR pull secret for `data`) take the same path; see [Other secrets](#other-secrets).

```text
scripts/mint-keys.sh ──► OCI Vault secret gcp-key-<workload>      (OCI, free default vault)
                              │  read as the node's instance principal
                              ▼
            External Secrets: ClusterSecretStore oci-vault ──► ExternalSecret gcp-key-<workload>
                              │
                              ▼
            Kubernetes Secret gcp-key-<workload>, data key key.json
            mounted at /var/secrets/gcp/key.json, GOOGLE_APPLICATION_CREDENTIALS points at it
```

| Workload | GCP service account | Vault secret and Kubernetes Secret | Namespace |
| --- | --- | --- | --- |
| extractor | `sa-extractor` | `gcp-key-extractor` | `data` |
| spark-drain | `sa-spark-drain` | `gcp-key-spark-drain` | `data` |
| airflow | `sa-airflow` | `gcp-key-airflow` | `data` |
| mcp-server | `sa-mcp-server` | `gcp-key-mcp-server` | `sportsagentic` |

`sa-spark-runner` never gets a key; it only runs Serverless Spark batches inside GCP.

## What `modules/secrets` creates

- An OCI Vault of the `DEFAULT` (shared) type and a software-protected AES-256 master key. Both
  are free. No virtual private vault.
- An IAM policy that lets the node dynamic group `read secret-bundles` in that vault only.
- The External Secrets Operator (chart `external-secrets` 2.14.0, multi-arch images) in namespace
  `external-secrets`. All three pods (controller, webhook, cert controller) have CPU and memory
  requests and limits, with memory limits of 128Mi.
- A small local chart, `modules/secrets/charts/oci-vault-sync`, with:
  - the `ClusterSecretStore` `oci-vault` (Oracle provider, `principalType: InstancePrincipal`),
    usable only from the `data` and `sportsagentic` namespaces;
  - seven `ExternalSecret`s, refreshed hourly, each copying one whole vault secret into one data
    key: the four GCP keys (data key `key.json`) and the three [other secrets](#other-secrets).
    An entry may set its own data key (`secretKey`) and Secret `type`; a type other than
    `Opaque` is set through `target.template.type`.

The vault secrets themselves are not OpenTofu resources: their content would land in state.
Until `mint-keys.sh` and `put-secret.sh` have run, the ExternalSecrets report
`SecretSyncedError`. That is expected.

The `data` namespace is created by the data platform module, and `sportsagentic` by the platform
module. This module only references them.

## Minting the keys (first time)

Run after both stacks are applied. You need `gcloud` (Owner on the GCP project), the OCI CLI
(allowed to manage secrets in the compartment) and `jq`.

```bash
export GCP_PROJECT=sports-agent-511915
export OCI_VAULT_OCID="$(tofu output -raw secrets_vault_id)"         # root stack
export OCI_VAULT_KEY_OCID="$(tofu output -raw secrets_master_key_id)" # root stack
export OCI_COMPARTMENT_OCID=...                                     # compartment_id from terraform.tfvars
export OCI_CLI_REGION=us-chicago-1

scripts/mint-keys.sh --dry-run all   # shows what it would do; calls no API
scripts/mint-keys.sh all
```

Per workload, the script:

1. creates a key for `sa-<workload>` and pipes it, in memory, into the vault secret
   `gcp-key-<workload>` (created on first run, a new current version after that);
2. reads the stored key's ID back from the vault;
3. deletes every other user-managed key of that service account.

The key is written by `gcloud` to a pipe, wrapped into the request body by `jq` in memory, and
read by the OCI CLI from stdin. It never touches disk, shell history, the terminal, or any
process's argument list.

## Rotating (every 90 days)

Rerun the script. The new key reaches each Kubernetes Secret within an hour (`refreshInterval`),
or at once if you force a sync:

```bash
kubectl annotate externalsecret gcp-key-airflow -n data force-sync="$(date +%s)" --overwrite
```

Pods started per run (extractor Jobs, the drain pod) pick the new key up on their next run.
Long-running pods (Airflow, the MCP server) keep the key they loaded at start-up, and the default
run deletes that key straight away. To rotate them without a gap:

```bash
scripts/mint-keys.sh --keep-old-keys all  # new key into the vault, old keys stay valid
# force-sync the ExternalSecrets (above), then restart the long-running pods:
kubectl rollout restart deployment/sportsagentic -n sportsagentic
# ...and the Airflow deployments in namespace data
scripts/mint-keys.sh --prune-only all     # delete every key except the one in the vault
```

`--prune-only` deletes nothing if the key in the vault is not one of the service account's keys.

If a run fails after `gcloud` created a key but before the vault stored it, that key is left
unused. The next normal run deletes it.

## Using a key in a workload

```yaml
env:
  - name: GOOGLE_APPLICATION_CREDENTIALS
    value: /var/secrets/gcp/key.json
volumeMounts:
  - name: gcp-key
    mountPath: /var/secrets/gcp
    readOnly: true
volumes:
  - name: gcp-key
    secret:
      secretName: gcp-key-extractor   # gcp-key-<workload>
```

Mount the whole directory (no `subPath`), so the kubelet updates the file after a rotation.

## Other secrets

Vault secret name = Kubernetes Secret name. The values are written by you with
`scripts/put-secret.sh <name>`, never by OpenTofu. The script accepts only these three names.

| Secret | Namespace | Type | Data key | Used by |
| --- | --- | --- | --- | --- |
| `cfbd-api-key` | `data` | `Opaque` | `CFBD_API_KEY` | extractor, poller |
| `telemetry-salt` | `sportsagentic` | `Opaque` | `TELEMETRY_SALT` | orchestrator (telemetry `user_key`) |
| `ocir-pull` | `data` | `kubernetes.io/dockerconfigjson` | `.dockerconfigjson` | every `data` pod pulling from OCIR |

The hand-made `ocir-pull` in `sportsagentic` stays as it is. Do not create `ocir-pull` in `data`
by hand: External Secrets owns it there.

`put-secret.sh` reads the value from a hidden prompt (asked twice) or from stdin, never from the
command line. It never echoes the value or writes it to disk, and creates the vault secret on the
first run and a new current version after that. It uses the same inputs as `mint-keys.sh`
(`OCI_VAULT_OCID`, `OCI_VAULT_KEY_OCID`, `OCI_COMPARTMENT_OCID`, `OCI_CLI_REGION`, exported as in
[Minting the keys](#minting-the-keys-first-time)); `--dry-run` reads and checks the value and
calls no API.

```bash
# CFBD API key: paste it at the hidden prompt
scripts/put-secret.sh cfbd-api-key

# Telemetry salt: generated and stored without being shown (at least 32 characters).
# Set it once: a new salt changes every user_key from then on.
openssl rand -hex 32 | scripts/put-secret.sh telemetry-salt

# OCIR pull secret for data: copy the working one from sportsagentic. Run it as one pipe,
# so the value never reaches the terminal.
kubectl -n sportsagentic get secret ocir-pull -o jsonpath='{.data.\.dockerconfigjson}' \
  | base64 -d | scripts/put-secret.sh ocir-pull
```

Or build `ocir-pull` from an OCIR auth token (the token is read hidden and only piped; works in
zsh and bash):

```bash
printf 'OCIR username (<tenancy-namespace>/<user name>): '; read -r u
printf 'OCIR auth token: '; stty -echo; read -r t; stty echo; echo
printf '%s' "$t" \
  | jq -Rc --arg u "$u" '{auths: {"ord.ocir.io": {username: $u, password: ., auth: (($u + ":" + .) | @base64)}}}' \
  | scripts/put-secret.sh ocir-pull
unset t u
```

To change a value later, rerun the same command. The Secret updates within an hour, or at once
with the `force-sync` annotation the script prints. Pods read `CFBD_API_KEY` and `TELEMETRY_SALT`
as environment variables at start-up, so restart them after a change.

## Security notes

- **Instance principal.** The cluster is basic, so it has no workload identity. External Secrets
  authenticates to OCI as the worker node, which means any pod on that node could also reach the
  instance metadata service and read every secret in this vault. The policy limits that to this
  one vault; it cannot be narrowed to a single pod without an enhanced cluster.
- **Dynamic group.** The policy names the dynamic group passed as `reader_dynamic_group_name`. It
  must match the worker node, or the vault answers `NotAuthorizedOrNotFound`.
- **Store scope.** The `ClusterSecretStore` refuses ExternalSecrets from any namespace other than
  `data` and `sportsagentic`.
- **Kubernetes RBAC.** Anyone who can read Secrets in `data` or `sportsagentic` can read the
  secrets in that namespace. In `sportsagentic` that includes the app deployer role.
- Never print a secret: no `kubectl get secret -o yaml`, no `oci secrets secret-bundle get` to the
  terminal, no `set -x` around the scripts.

## Checking it works

```bash
kubectl get clustersecretstore oci-vault              # STATUS Valid, READY True
kubectl get externalsecrets -A                        # all seven: STATUS SecretSynced, READY True
kubectl describe externalsecret gcp-key-airflow -n data
kubectl get secret ocir-pull -n data -o jsonpath='{.type}'  # kubernetes.io/dockerconfigjson
```

## Teardown

`tofu destroy` on the root stack removes both Helm releases, the policy, the key and the vault.
OCI does not delete a vault or key at once: it schedules deletion (30 days by default) and the
vault can be restored until then. Destroying the `gcp/` stack deletes the service accounts and
with them every key minted for them.
