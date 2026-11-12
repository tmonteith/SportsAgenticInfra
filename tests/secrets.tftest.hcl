mock_provider "oci" {}
mock_provider "kubernetes" {}
mock_provider "helm" {}

variables {
  tenancy_ocid              = "ocid1.tenancy.oc1..test"
  compartment_id            = "ocid1.compartment.oc1..test"
  compartment_name          = "sportsagentic"
  identity_domain_name      = "Default"
  prefix                    = "sportsagentic"
  region                    = "us-chicago-1"
  reader_dynamic_group_name = "sportsagentic-mcp-nodes-dg"
  data_namespace            = "data"
  app_namespace             = "sportsagentic"
}

run "test_secrets_module_plan" {
  command = plan

  module {
    source = "./modules/secrets"
  }

  # Vault and key stay on the free tier
  assert {
    condition     = oci_kms_vault.this.vault_type == "DEFAULT"
    error_message = "Vault must be the free DEFAULT (shared) type, never a virtual private vault"
  }

  assert {
    condition     = oci_kms_key.this.protection_mode == "SOFTWARE"
    error_message = "Master key must be software-protected"
  }

  assert {
    condition     = oci_kms_key.this.key_shape[0].algorithm == "AES" && oci_kms_key.this.key_shape[0].length == 32
    error_message = "Master key must be AES-256"
  }

  # External Secrets Operator
  assert {
    condition     = kubernetes_namespace_v1.external_secrets.metadata[0].name == "external-secrets"
    error_message = "External Secrets namespace must be external-secrets"
  }

  assert {
    condition     = helm_release.external_secrets.chart == "external-secrets" && helm_release.external_secrets.version == "2.14.0"
    error_message = "External Secrets chart must be pinned to 2.14.0"
  }

  assert {
    condition = alltrue([
      for r in [
        yamldecode(helm_release.external_secrets.values[0]).resources,
        yamldecode(helm_release.external_secrets.values[0]).webhook.resources,
        yamldecode(helm_release.external_secrets.values[0]).certController.resources,
      ] : r.requests.cpu != "" && r.requests.memory != "" && r.limits.cpu != "" && endswith(r.limits.memory, "Mi") && tonumber(trimsuffix(r.limits.memory, "Mi")) <= 128
    ])
    error_message = "Every External Secrets pod needs CPU and memory requests and limits, with a memory limit of at most 128Mi"
  }

  assert {
    condition     = helm_release.oci_vault_sync.namespace == "external-secrets"
    error_message = "The ClusterSecretStore chart must be released into the External Secrets namespace"
  }

  # Contract: four secrets, vault name = Kubernetes name, in the right namespaces
  assert {
    condition = jsonencode(output.gcp_key_secrets) == jsonencode([
      { name = "gcp-key-extractor", namespace = "data" },
      { name = "gcp-key-spark-drain", namespace = "data" },
      { name = "gcp-key-airflow", namespace = "data" },
      { name = "gcp-key-mcp-server", namespace = "sportsagentic" },
    ])
    error_message = "GCP key secrets must be gcp-key-{extractor,spark-drain,airflow} in data and gcp-key-mcp-server in sportsagentic"
  }
}

run "test_secrets_module_apply_with_mocks" {
  command = apply

  module {
    source = "./modules/secrets"
  }

  override_resource {
    target = oci_kms_vault.this
    values = {
      id                  = "ocid1.vault.oc1..test"
      management_endpoint = "https://test-management.kms.us-chicago-1.oraclecloud.com"
    }
  }

  assert {
    condition     = oci_identity_policy.secrets_read.statements == tolist(["Allow dynamic-group sportsagentic-mcp-nodes-dg to read secret-bundles in compartment sportsagentic where target.vault.id = 'ocid1.vault.oc1..test'"])
    error_message = "IAM policy must only let the node dynamic group read secret bundles in this vault"
  }

  assert {
    condition     = yamldecode(helm_release.oci_vault_sync.values[0]).clusterSecretStore.vault == "ocid1.vault.oc1..test"
    error_message = "ClusterSecretStore must point at the module's vault"
  }

  assert {
    condition     = yamldecode(helm_release.oci_vault_sync.values[0]).clusterSecretStore.region == "us-chicago-1"
    error_message = "ClusterSecretStore region must be the vault's region"
  }

  assert {
    condition     = toset(yamldecode(helm_release.oci_vault_sync.values[0]).clusterSecretStore.namespaces) == toset(["data", "sportsagentic"])
    error_message = "Only the data and sportsagentic namespaces may use the ClusterSecretStore"
  }

  assert {
    condition     = length(yamldecode(helm_release.oci_vault_sync.values[0]).externalSecrets) == 4
    error_message = "There must be exactly one ExternalSecret per workload"
  }
}
