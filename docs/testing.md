# Testing Guide: SportsAgentic Infrastructure

This repository includes a multi-tiered automated testing framework to guarantee stability, security compliance, and correctness of all cloud resources.

---

## 🧪 Testing Pyramid

```
                       ┌─────────────────────────────┐
                       │     Terratest Live E2E      │  (Real OCI sandbox, kubectl checks)
                       ├─────────────────────────────┤
                       │  OpenTofu Native Unit Tests │  (Mocked provider, zero cost, < 2s)
                       ├─────────────────────────────┤
                       │ Checkov & Trivy Security    │  (Static misconfiguration analysis)
                       ├─────────────────────────────┤
                       │  tofu fmt & tofu validate   │  (Syntax, types, and formatting)
                       └─────────────────────────────┘
```

---

## 1. Native OpenTofu Unit Tests (`tofu test`)

Tests module inputs, CIDR math, OKE node pool shapes, taints, NoSQL throughput limits, and scoped IAM policy rules without cloud credentials or API calls using OpenTofu's native `mock_provider`.

### Test Files
* [`tests/network.tftest.hcl`](../tests/network.tftest.hcl): Asserts VCN CIDR, DNS label, public subnet routing to IGW, private subnet routing to NAT/Service Gateways, and strict `prohibit_public_ip_on_vnic` enforcement on worker nodes.
* [`tests/oke.tftest.hcl`](../tests/oke.tftest.hcl): Asserts `BASIC_CLUSTER` type, Flannel overlay networking, services pool ARM `VM.Standard.A1.Flex` (2 OCPU / 12 GB RAM), and model pool sitting at `size = 0` (4 OCPU / 24 GB RAM, tainted `workload-role=model:NoSchedule`).
* [`tests/platform.tftest.hcl`](../tests/platform.tftest.hcl): Asserts NoSQL table limits (50 read/write units, 25 GB storage), read-only MCP NoSQL IAM policy statements, public DNS zone `sportagentic.dev`, OCIR repository names, and K8s namespaces/RBAC.

### Running Unit Tests Locally
```bash
tofu test
```

---

## 2. Checkov IaC Security & Compliance

Checkov scans the OpenTofu code for cloud security misconfigurations, CIS benchmark compliance, and least-privilege violations.

### Configuration (`.checkov.yaml`)
* Framework: `terraform`
* Documented exception skips:
  * `CKV_OCI_9`: Bucket CMK encryption skipped for the bootstrap state bucket to maintain Always Free tier eligibility and avoid circular KMS dependencies.
  * `CKV_OCI_17`: Inbound security lists statelessness skipped because OKE Kubernetes networking (Flannel overlay, kubelet port 10250, and NodePorts) mandates stateful connection tracking.

### Running Checkov Locally
```bash
checkov --config-file .checkov.yaml
```

---

## 3. Terratest Suite (Go)

Terratest provides programmatic infrastructure testing written in Go under [`test/`](../test/).

### Suite Structure
* [`test/network_test.go`](../test/network_test.go): Validates VCN and subnet outputs.
* [`test/oke_test.go`](../test/oke_test.go): Validates OKE cluster creation, writes kubeconfig, and runs `k8s.GetNodes` via `client-go` to verify worker node readiness.
* [`test/platform_test.go`](../test/platform_test.go): Validates NoSQL table, OCIR repos, and DNS nameservers.

### Running Unit Plans (No OCI Account Required)
```bash
cd test
go test -v -short -run "Test.*Plan" .
```

### Running Live Integration Tests (Against Sandbox OCI Compartment)
When your OCI account is ready, set the environment variables and run:
```bash
export OCI_TENANCY_OCID="ocid1.tenancy.oc1..xxxx"
export OCI_COMPARTMENT_OCID="ocid1.compartment.oc1..xxxx"
export OCI_REGION="us-ashburn-1"
export RUN_INTEGRATION_TESTS="true"

cd test
go test -v -timeout 45m .
```
Terratest will provision the infrastructure, verify all assertions, and execute `defer terraform.Destroy` to tear down all resources automatically.
