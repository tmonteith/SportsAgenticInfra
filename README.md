# 🏟️ SportsAgentic Infrastructure (OCI & OpenTofu)

Production-grade Infrastructure-as-Code (IaC) repository for **SportsAgentic**, managing cloud infrastructure on Oracle Cloud Infrastructure (OCI) using **OpenTofu**.

---

## 🏛️ Architecture Overview

```
                                  INTERNET
                                      │
                         [Porkbun: sportagentic.dev]
                                      │ (NS Delegation)
                                      ▼
                        ┌───────────────────────────┐
                        │    OCI Public DNS Zone    │
                        │    (sportagentic.dev)     │
                        └─────────────┬─────────────┘
                                      │
                                      ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                    OCI Tenancy / Compartment: sportsagentic                  │
│                                                                              │
│   Virtual Cloud Network (10.0.0.0/16)                                        │
│   ├─ Internet Gateway & NAT Gateway & Service Gateway (OSN)                  │
│   │                                                                          │
│   ├─ [Public Subnet: 10.0.1.0/24]                                            │
│   │   └─ OCI Flexible Load Balancer (ingress-nginx)                          │
│   │                                                                          │
│   ├─ [Public Subnet: 10.0.0.0/28]                                            │
│   │   └─ OKE Control Plane Endpoint (Kubernetes v1.31)                       │
│   │                                                                          │
│   └─ [Private Subnet: 10.0.10.0/24]                                          │
│       ├─ Services Node Pool (VM.Standard.A1.Flex - 2 OCPU / 12 GB RAM)       │
│       │   ├─ Ingress-Nginx Controller                                        │
│       │   ├─ Cert-Manager (Let's Encrypt TLS)                                │
│       │   └─ SportsAgentic MCP Server Pod (Namespace: sportsagentic)         │
│       │                                                                      │
│       └─ Model Node Pool (VM.Standard.A1.Flex - 4 OCPU / 24 GB RAM)          │
│           └─ Sits at size = 0 (Tainted: workload-role=model:NoSchedule)      │
│                                                                              │
│   OCI Platform Services:                                                     │
│   ├─ OCIR Repositories: sportsagentic/mcp-server, sportsagentic/agent-model  │
│   └─ OCI NoSQL Table: sportsagentic_cfb (Scoped IAM Read Access)             │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 📦 Directory Structure

```text
SportsAgenticInfra/
├── .github/
│   └── workflows/
│       ├── ci-pr.yml              # PR validation (fmt, validate, Trivy IaC security, plan comment)
│       ├── cd-apply.yml           # Gated apply on merge to main via production approval environment
│       └── drift-check.yml        # Nightly scheduled drift detection and GitHub issue alerting
├── bootstrap/                     # I-0: Foundation stack (state bucket, CI user, IAM policies)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── modules/
│   ├── network/                   # I-1: VCN, subnets, IGW, NAT GW, Service GW, Route Tables, Security Lists
│   ├── iam/                       # I-1: OKE worker node dynamic groups, cluster join policies, app CI user
│   ├── oke/                       # I-2: OKE cluster, services node pool, tainted model pool @ size 0
│   └── platform/                  # I-3: OCIR repos, NoSQL table + IAM read policy, DNS zone, Ingress, cert-manager
├── docs/
│   ├── authentication.md          # CI/CD authentication architecture & OIDC limitation analysis
│   ├── bootstrap.md               # Step-by-step bootstrap execution guide
│   └── dns-setup.md               # Porkbun to OCI DNS delegation guide
├── main.tf                        # Root orchestration
├── backend.tf                     # S3-compatible remote state on OCI Object Storage
├── providers.tf                   # oracle/oci, kubernetes, helm providers
├── variables.tf                   # Root configuration variables
├── outputs.tf                     # I-4: Exported values for application pipelines
├── terraform.tfvars.example
├── .tflint.hcl
└── .gitignore
```

---

## 🚀 Getting Started

### 1. Run the Bootstrap Stack (One-Time Setup)
Follow [`docs/bootstrap.md`](./docs/bootstrap.md) to initialize the OCI compartment, state storage bucket, and CI/CD credentials:

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# Fill in tenancy_ocid and region
tofu init
tofu apply
eval "$(tofu output -raw github_secrets_export_script)"
```

### 2. CI/CD Automation
* **Pull Requests**: Every PR against `main` automatically runs formatting checks, configuration validation, Trivy security scanning, and posts an interactive plan diff comment.
* **Landing Changes**: Merging into `main` generates a plan and pauses at the `production` GitHub Environment. Repository owners (`tmonteith`) approve the apply directly in GitHub.
* **Drift Detection**: Runs daily at 06:00 UTC and alerts via GitHub Issues if manual changes occur in OCI.

### 3. Domain Delegation
Follow [`docs/dns-setup.md`](./docs/dns-setup.md) to point `sportagentic.dev` from Porkbun to your OCI Anycast nameservers.

