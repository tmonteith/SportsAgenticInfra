# GCP lakehouse stack (`gcp/`)

A separate OpenTofu root stack for the GCP side of the SportsAgentic lakehouse. It has its own
state (in GCS) and its own providers; the OCI stack at the repository root is unaffected.

| What | Name |
| --- | --- |
| Region | `us-central1` (every resource, single-region buckets only) |
| Buckets | `<proj>-sa-landing`, `<proj>-sa-warehouse`, `<proj>-sa-gold`, `<proj>-sa-jobs` |
| Iceberg REST catalog | `sa_catalog` (BigLake / Lakehouse runtime catalog) |
| Namespaces | `bronze`, `silver` in the warehouse bucket; `gold` in the gold bucket |
| BigQuery name | `<proj>.sa_catalog.<namespace>.<table>` |
| Service accounts | `sa-extractor`, `sa-spark-drain`, `sa-airflow`, `sa-mcp-server`, `sa-spark-runner` |
| Budget | `sportsagentic-lakehouse`, alerts at $5, $10 and $20 by email |
| State | `gs://sports-agent-511915-sa-tfstate`, prefix `gcp` |

No service account key is ever created here. Keys are minted by `scripts/mint-keys.sh` straight
into OCI Vault (see [docs/secrets.md](../docs/secrets.md)), so none can reach OpenTofu state.

## First run

Prerequisites: `gcloud` and OpenTofu (>= 1.8), Owner on the project, and the project linked to
the billing account.

```bash
# 1. Once: enable the bootstrap APIs and create the versioned state bucket (idempotent).
scripts/bootstrap-gcp-state.sh --project sports-agent-511915

# 2. Credentials for OpenTofu.
gcloud auth application-default login

# 3. Inputs: project ID, billing account display name, alert email. terraform.tfvars is gitignored.
cd gcp
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

# 4. Plan, review, apply.
tofu init
tofu plan -out=tfplan
tofu apply tfplan
```

The provider sets `user_project_override = true` with the project as `billing_project`. With
user credentials, the BigLake Iceberg IAM resources and the billing budget return 403 without it.

## APIs

The stack enables Storage, BigLake, BigQuery, Dataproc, IAM and Billing Budgets, plus Cloud
Monitoring (`monitoring.googleapis.com`), which owns the email notification channel the budget
alerts go to. The bootstrap script enables what must exist before the first plan: Service Usage,
Cloud Resource Manager, Cloud Billing (the stack looks up the billing account by display name)
and Storage. APIs are never disabled on destroy.

## Catalog design

- **Multiple-bucket catalog** (`CATALOG_TYPE_BIGLAKE`). Its default location is the warehouse
  bucket and the gold bucket is a second allowed location. Single-bucket catalogs must be named
  after their bucket and cannot span two buckets, so they cannot give us `sa_catalog`.
- **Namespace locations.** `bronze` and `silver` store tables under
  `gs://<proj>-sa-warehouse/<namespace>`, `gold` under `gs://<proj>-sa-gold/gold`.
- **End-user credentials** (`CREDENTIAL_MODE_END_USER`). Every caller uses its own storage
  access, so each identity's bucket grants are the real boundary. Credential vending would have
  the catalog's own service account read every bucket for everyone.
- **BigQuery** reads tables by `<proj>.sa_catalog.<namespace>.<table>`. Table metadata lives in
  `us-central1`, so queries must run in location `us-central1`, not the `US` multi-region.

Spark clients (Iceberg 1.10 or later) use:

| Property | Value |
| --- | --- |
| `uri` | `https://biglake.googleapis.com/iceberg/v1/restcatalog` (output `iceberg_rest_catalog_uri`) |
| `warehouse` | `bl://projects/<proj>/catalogs/sa_catalog` (output `iceberg_warehouse`) |
| `rest.auth.type` | `org.apache.iceberg.gcp.auth.GoogleAuthManager` |
| `io-impl` | `org.apache.iceberg.gcp.gcs.GCSFileIO` |

If a client sends `header.x-goog-user-project`, its identity also needs
`serviceusage.services.use` on the project. Without the header, a service account key bills its
own project, which is this one.

## Access (least privilege)

| Service account | Grants | Where |
| --- | --- | --- |
| `sa-extractor` | `storage.objectCreator` | landing bucket |
| `sa-spark-drain` | `storage.objectAdmin` | warehouse bucket |
| | `biglake.editor` | namespaces `bronze`, `silver` |
| | custom `saBiglakeCatalogGetter` (`biglake.catalogs.get` only) | catalog `sa_catalog` |
| `sa-airflow` | custom `saDataprocBatchSubmitter` (create, get, list, cancel batches; get, cancel operations) | project |
| | `iam.serviceAccountUser` | `sa-spark-runner` only |
| | `storage.objectViewer` | landing bucket |
| `sa-spark-runner` | `storage.objectAdmin` | warehouse and gold buckets |
| | `storage.objectViewer` | landing and jobs buckets |
| | `biglake.editor` | catalog `sa_catalog` |
| | `dataproc.worker` | project |
| `sa-mcp-server` | `bigquery.jobUser` | project |
| | `biglake.viewer` | namespace `gold` |
| | custom `saBiglakeCatalogGetter` | catalog `sa_catalog` |
| | `storage.objectViewer` | gold bucket |

`sa-mcp-server` has no BigLake permission on `bronze` or `silver` and no access to the warehouse
bucket, so reading `silver.plays` fails on both checks.

Notes:

- `roles/dataproc.worker` includes object read and write on every bucket in the project (Dataproc
  needs it for its staging buckets). `sa-spark-runner` has no key and only runs inside GCP.
- `sa-extractor` can create objects but not list or read them. Its "skip what is already landed"
  check therefore cannot list the landing bucket.

## Tests

`gcp/tests/gcp.tftest.hcl` checks the contract names, bucket settings, namespace locations, the
MCP identity's gold-only access and the budget thresholds against a mocked provider:

```bash
cd gcp && tofu init -backend=false && tofu test
```

## Outputs

`bucket_names`, `catalog_name`, `iceberg_namespaces`, `iceberg_rest_catalog_uri`,
`iceberg_warehouse`, `service_account_emails`, `billing_budget_name`.

## Not managed here

- **Serverless Spark networking.** Batches run in the `default` VPC unless told otherwise, and
  their subnet in `us-central1` needs Private Google Access. Enable it once, or give the batches
  another subnet: `gcloud compute networks subnets update default --region=us-central1 --enable-private-ip-google-access`.
- **Keys.** See [docs/secrets.md](../docs/secrets.md).

## Teardown

```bash
cd gcp && tofu destroy
```

This deletes all four buckets with their contents (`force_destroy = true`), the catalog and its
namespaces, the service accounts (and so every key minted for them), the budget and the
notification channel. APIs stay enabled. Custom roles are soft-deleted: recreating them within
7 days undeletes them, but between 7 and 44 days after deletion their IDs cannot be reused.

The state bucket is never destroyed by OpenTofu. Remove it by hand once nothing uses it:

```bash
gcloud storage rm --recursive gs://sports-agent-511915-sa-tfstate
```
