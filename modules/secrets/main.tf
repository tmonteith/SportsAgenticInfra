locals {
  domain_prefix = (var.identity_domain_name != "" && lower(var.identity_domain_name) != "default") ? "'${var.identity_domain_name}'/" : ""
  reader_dg_ref = "${local.domain_prefix}${var.reader_dynamic_group_name}"

  # Vault secret name = Kubernetes Secret name = gcp-key-<workload> (contract).
  # The vault secrets themselves are written by scripts/mint-keys.sh, never by
  # OpenTofu, so no key material reaches state.
  workload_secrets = [
    { name = "gcp-key-extractor", namespace = var.data_namespace },
    { name = "gcp-key-spark-drain", namespace = var.data_namespace },
    { name = "gcp-key-airflow", namespace = var.data_namespace },
    { name = "gcp-key-mcp-server", namespace = var.app_namespace },
  ]

  # Every External Secrets pod gets requests and limits; memory limits stay at
  # or below 128Mi.
  external_secrets_values = {
    installCRDs = true
    concurrent  = 1
    resources = {
      requests = { cpu = "10m", memory = "64Mi" }
      limits   = { cpu = "200m", memory = "128Mi" }
    }
    webhook = {
      resources = {
        requests = { cpu = "10m", memory = "32Mi" }
        limits   = { cpu = "100m", memory = "128Mi" }
      }
    }
    certController = {
      resources = {
        requests = { cpu = "10m", memory = "32Mi" }
        limits   = { cpu = "100m", memory = "128Mi" }
      }
    }
  }
}

# 1. OCI Vault (DEFAULT = shared, free) and a software-protected master key
resource "oci_kms_vault" "this" {
  compartment_id = var.compartment_id
  display_name   = "${var.prefix}-vault"
  vault_type     = "DEFAULT"

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

resource "oci_kms_key" "this" {
  compartment_id      = var.compartment_id
  display_name        = "${var.prefix}-secrets-key"
  management_endpoint = oci_kms_vault.this.management_endpoint
  protection_mode     = "SOFTWARE"

  key_shape {
    algorithm = "AES"
    length    = 32
  }

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# 2. Let the worker nodes (instance principal) read secret bundles in this vault only
resource "oci_identity_policy" "secrets_read" {
  compartment_id = var.tenancy_ocid
  name           = "${var.prefix}-vault-secrets-read-policy"
  description    = "Lets External Secrets on the OKE nodes read secret bundles in the SportsAgentic vault only"

  statements = [
    "Allow dynamic-group ${local.reader_dg_ref} to read secret-bundles in compartment ${var.compartment_name} where target.vault.id = '${oci_kms_vault.this.id}'",
  ]

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# 3. External Secrets Operator
resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"             = "external-secrets"
      "app.kubernetes.io/part-of"          = "sportsagentic"
      "pod-security.kubernetes.io/enforce" = "baseline"
    }
  }
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.external_secrets_chart_version
  namespace  = kubernetes_namespace_v1.external_secrets.metadata[0].name

  values = [yamlencode(local.external_secrets_values)]
}

# 4. ClusterSecretStore (OCI Vault, instance principal) and one ExternalSecret
#    per workload. Installed after the operator because they need its CRDs and
#    validating webhook.
resource "helm_release" "oci_vault_sync" {
  name       = "oci-vault-sync"
  chart      = "${path.module}/charts/oci-vault-sync"
  namespace  = kubernetes_namespace_v1.external_secrets.metadata[0].name
  depends_on = [helm_release.external_secrets, oci_identity_policy.secrets_read]

  values = [yamlencode({
    clusterSecretStore = {
      name       = var.cluster_secret_store_name
      region     = var.region
      vault      = oci_kms_vault.this.id
      namespaces = distinct([for s in local.workload_secrets : s.namespace])
    }
    refreshInterval = var.refresh_interval
    externalSecrets = local.workload_secrets
  })]
}
