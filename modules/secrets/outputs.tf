output "vault_id" {
  description = "OCID of the OCI Vault holding the GCP service account keys (mint-keys.sh --vault-id)."
  value       = oci_kms_vault.this.id
}

output "master_key_id" {
  description = "OCID of the software-protected master key that encrypts the vault secrets (mint-keys.sh --key-id)."
  value       = oci_kms_key.this.id
}

output "namespace" {
  description = "Kubernetes namespace of the External Secrets Operator."
  value       = kubernetes_namespace_v1.external_secrets.metadata[0].name
}

output "cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore backed by the OCI Vault."
  value       = var.cluster_secret_store_name
}

output "gcp_key_secrets" {
  description = "Synced GCP key Secrets: name (same in the vault and in Kubernetes) and namespace. Each has one data key, key.json."
  value       = local.workload_secrets
}
