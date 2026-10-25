# Bootstrap Guide: Foundations & CI/CD Credentials

The `bootstrap/` OpenTofu stack creates the foundational OCI resources that cannot be created by the CI/CD pipeline itself:
* Dedicated workload compartment (`sportsagentic`)
* Private, versioned Object Storage bucket for OpenTofu state (`sportsagentic-tfstate`)
* Least-privilege CI/CD IAM user (`sportsagentic-ci`), group, RSA API signing key, and S3 Customer Secret Key
* IAM policies granting scoped management permissions

---

## Prerequisites

1. An OCI account with tenancy administrator permissions (or permissions to create compartments and IAM groups).
2. [OpenTofu CLI](https://opentofu.org/) (`tofu`) installed locally.
3. [GitHub CLI](https://cli.github.com/) (`gh`) authenticated with repository permissions (`gh auth login`).
4. [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) (`oci`) installed locally and available in `$PATH` (required by the Kubernetes and Helm providers to generate OKE authentication tokens during plan/apply).

---

## Step 1: Configure Bootstrap Variables

Navigate to the `bootstrap/` directory and create your `terraform.tfvars`:

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your OCI Tenancy OCID and region:
```hcl
tenancy_ocid         = "ocid1.tenancy.oc1..aaaaaaaaxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
region               = "us-ashburn-1"
identity_domain_name = "Default" # Leave as "Default" for Identity Domains, or "" for classic IAM
compartment_name     = "sportsagentic"
tfstate_bucket_name  = "sportsagentic-tfstate"
```

---

## Step 2: Initialize and Apply

The bootstrap stack uses local state (`terraform.tfstate`) since the remote bucket does not exist yet:

```bash
tofu init
tofu plan -out=tfplan
tofu apply tfplan
```

---

## Step 3: Populate GitHub Secrets Automatically

After the apply completes, run the generated script to export all required secrets to GitHub:

```bash
eval "$(tofu output -raw github_secrets_export_script)"
```

Or manually verify the secrets:
```bash
gh secret list
```

You should see:
- `OCI_TENANCY_OCID`
- `OCI_USER_OCID`
- `OCI_FINGERPRINT`
- `OCI_PRIVATE_KEY`
- `OCI_REGION`
- `OCI_COMPARTMENT_OCID`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `TFSTATE_BUCKET`
- `TFSTATE_S3_ENDPOINT`

---

## Step 4: Secure Local Bootstrap State

Once the bootstrap resources are created, store `bootstrap/terraform.tfstate` in a secure location (e.g. encrypted password manager or private administrative vault). Do **not** commit `terraform.tfstate` to Git (it is blocked by `.gitignore`).

---

## Step 5: Connect Root Stack to Remote State

When you are ready to provision the main infrastructure, return to the repository root and initialize the S3 remote state backend using the values output by bootstrap:

```bash
cd ..

# Retrieve your namespace-scoped endpoint from bootstrap output:
S3_ENDPOINT=$(tofu -chdir=bootstrap output -raw tfstate_s3_endpoint)
S3_ACCESS_KEY=$(tofu -chdir=bootstrap output -raw s3_access_key_id)
S3_SECRET_KEY=$(tofu -chdir=bootstrap output -raw s3_secret_access_key)
STATE_BUCKET=$(tofu -chdir=bootstrap output -raw tfstate_bucket_name)
OCI_REGION=$(tofu -chdir=bootstrap output -raw region)

tofu init \
  -backend-config="bucket=$STATE_BUCKET" \
  -backend-config="endpoint=$S3_ENDPOINT" \
  -backend-config="region=$OCI_REGION" \
  -backend-config="access_key=$S3_ACCESS_KEY" \
  -backend-config="secret_key=$S3_SECRET_KEY"
```

> **Note on OCI S3 Endpoints:** OCI requires your tenancy's Object Storage Namespace as a prefix in the endpoint URL (`https://<namespace>.compat.objectstorage.<region>.oraclecloud.com`). Omitting the namespace results in a TLS certificate mismatch error.

