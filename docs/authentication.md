# CI/CD Authentication & OCI OIDC Federation Analysis

This document describes how GitHub Actions authenticates to Oracle Cloud Infrastructure (OCI) for OpenTofu automation, details the investigation into short-lived federated credentials (OIDC), documents current limitations, and outlines the chosen least-privilege key architecture and rotation procedures.

---

## 1. Authentication Architecture Overview

The continuous delivery pipeline manages infrastructure across two distinct layers:
1. **OpenTofu Provider (`oracle/oci`)**: Communicates with OCI REST APIs to provision compartments, VCNs, subnets, OKE clusters, NoSQL tables, and OCIR repositories.
2. **OpenTofu State Backend (`backend "s3"`)**: Communicates with OCI Object Storage via its Amazon S3-compatible API to store and lock state files.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        GitHub Actions Runner                           │
│                                                                        │
│   ┌───────────────────────────────────┐                                │
│   │   OpenTofu CLI (v1.8+)            │                                │
│   │                                   │                                │
│   │   ├─ oracle/oci Provider          │──(API Key Auth)────────────┐   │
│   │   │  - OCI_USER_OCID              │                            │   │
│   │   │  - OCI_TENANCY_OCID           │                            │   │
│   │   │  - OCI_FINGERPRINT            │                            │   │
│   │   │  - OCI_PRIVATE_KEY            │                            │   │
│   │   │  - OCI_REGION                 │                            │   │
│   │   │                               │                            │   │
│   │   └─ S3 Backend                   │──(Customer Secret Key)─────┼─┐ │
│   │      - AWS_ACCESS_KEY_ID          │                            │ │ │
│   │      - AWS_SECRET_ACCESS_KEY      │                            │ │ │
│   │      - S3 Endpoint (Object Storage)                            │ │ │
│   └───────────────────────────────────┘                            │ │ │
└────────────────────────────────────────────────────────────────────┼─┼─┘
                                                                     │ │
                                                                     ▼ ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      Oracle Cloud Infrastructure                       │
│                                                                        │
│   ┌────────────────────────────────┐  ┌────────────────────────────┐   │
│   │  OCI IAM / Identity Domains    │  │  OCI Object Storage (S3)   │   │
│   │  - sportsagentic-ci (User)     │  │  - sportsagentic-tfstate   │   │
│   │  - Scoped to compartment       │  │  - Native state locking    │   │
│   └────────────────────────────────┘  └────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. OIDC & Short-Lived Federated Credentials: Investigation & Limitations

We investigated whether GitHub Actions could use keyless OpenID Connect (OIDC) token exchange to eliminate static API keys.

### What OCI Supports
* OCI IAM Identity Domains supports **Workload Identity Federation (WIF)** and OAuth 2.0 Token Exchange ([RFC 8693](https://datatracker.ietf.org/doc/html/rfc8693)).
* An Identity Domain can register an `Identity Propagation Trust` configured with the GitHub OIDC issuer (`https://token.actions.githubusercontent.com`).
* A workflow with `permissions: id-token: write` can request a GitHub JWT and exchange it at the IDCS `/oauth2/v1/token` endpoint for a 60-minute **User Principal Session Token (UPST)**.
* The OCI CLI and Terraform OCI provider can accept this session token via `auth = "SecurityToken"` or `~/.oci/config`.

### Why Pure Keyless OIDC Cannot Be Used Today (Known Limitations)

1. **No Native OpenTofu/Terraform Provider Support**:
   * Unlike AWS, GCP, and Azure, the `oracle/oci` Terraform/OpenTofu provider does **not** natively support GitHub OIDC token exchange (tracked in [oracle/terraform-provider-oci#2298](https://github.com/oracle/terraform-provider-oci/issues/2298)).
   * To use it, every CI job must execute custom bootstrap scripts to authenticate with IDCS, handle token caching, and generate temporary `~/.oci/config` files before running OpenTofu.

2. **Residual Secrets in OCI Identity Domains**:
   * OCI's token-exchange endpoint requires authentication through an **OCI Confidential Application**.
   * The workflow must pass `client_id` and `client_secret` (or an assertion client secret) to perform the token exchange. As a result, static secrets cannot be completely eliminated from GitHub Secrets.

3. **Incompatibility with OpenTofu Remote State Backend (Critical Blocker)**:
   * OpenTofu does not yet have a native `oci` state backend ([opentofu/opentofu#1011](https://github.com/opentofu/opentofu/issues/1011)).
   * Remote state storage on OCI Object Storage relies on OpenTofu's `s3` backend.
   * OCI Object Storage’s S3 compatibility layer **strictly requires an OCI Customer Secret Key** (`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`).
   * The S3 API cannot authenticate using OCI Security Tokens or OAuth bearer tokens. Even if the OCI provider used OIDC, a static customer secret key would still be required for the state backend.

---

## 3. Implemented Approach: Narrowly Scoped API Signing Key

Because of the S3 backend and provider constraints, we implement a hardened, least-privilege static credential model:

### Least-Privilege IAM Scoping
* **Dedicated Service Account**: `sportsagentic-ci` user belonging to `sportsagentic-ci-group`.
* **Compartment Boundary**: The user is granted `manage all-resources in compartment sportsagentic`. It has **no** administrative permissions outside this compartment.
* **Tenancy-Level Scoping**: Tenancy permissions are strictly limited to read-only queries required by provider discovery (`read compartments in tenancy`, `inspect tenancy in tenancy`) and dynamic group management for OKE node registration.
* **State Bucket Isolation**: Object Storage permissions are restricted to the single `sportsagentic-tfstate` bucket:
  ```text
  Allow group sportsagentic-ci-group to manage objects in compartment sportsagentic where target.bucket.name = 'sportsagentic-tfstate'
  ```

---

## 4. Pipeline Security Controls

1. **GitHub Secrets Storage**:
   * `OCI_PRIVATE_KEY`
   * `OCI_FINGERPRINT`
   * `OCI_USER_OCID`
   * `OCI_TENANCY_OCID`
   * `OCI_REGION`
   * `OCI_COMPARTMENT_OCID`
   * `AWS_ACCESS_KEY_ID`
   * `AWS_SECRET_ACCESS_KEY`
   * `TFSTATE_BUCKET`
   * `TFSTATE_S3_ENDPOINT`

2. **Environment Protection Gate**:
   * All mutations (`tofu apply`) run inside the `production` GitHub Environment.
   * Deployment requires **explicit manual approval** from designated repository reviewers (`tmonteith`).
   * Pull request workflows only execute `tofu plan` in read-only mode.

3. **Nightly Drift Detection**:
   * Scheduled workflow runs `tofu plan -detailed-exitcode` daily to detect configuration drift without modifying live infrastructure.

---

## 5. Key Rotation Runbook (Zero Downtime)

To rotate the CI API key and S3 Customer Secret Key:

1. **Add a second API Key in OCI**:
   * Generate a new 2048-bit RSA key pair:
     ```bash
     openssl genrsa -out oci_ci_new.pem 2048
     openssl rsa -pubout -in oci_ci_new.pem -out oci_ci_new_public.pem
     ```
   * Add the public key to user `sportsagentic-ci` in OCI Console or CLI.
   * Note the new key's fingerprint.

2. **Generate a second S3 Customer Secret Key**:
   * In OCI Console -> User `sportsagentic-ci` -> Customer Secret Keys -> **Generate Secret Key**.
   * Note the new Access Key ID and Secret Access Key.

3. **Update GitHub Secrets**:
   ```bash
   gh secret set OCI_PRIVATE_KEY < oci_ci_new.pem
   gh secret set OCI_FINGERPRINT --body "<new_fingerprint>"
   gh secret set AWS_ACCESS_KEY_ID --body "<new_access_key_id>"
   gh secret set AWS_SECRET_ACCESS_KEY --body "<new_secret_key>"
   ```

4. **Verify CI**:
   * Run the drift check workflow via `gh workflow run drift-check.yml`.

5. **Revoke Old Keys**:
   * In OCI Console, delete the old API key and old Customer Secret Key.
