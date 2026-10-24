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
