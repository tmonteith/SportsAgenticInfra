output "vault_id" {
  description = "OCID of the OCI Vault holding the synced secrets (mint-keys.sh and put-secret.sh --vault-id)."
  value       = oci_kms_vault.this.id
}

output "master_key_id" {
  description = "OCID of the software-protected master key that encrypts the vault secrets (mint-keys.sh and put-secret.sh --key-id)."
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

output "external_secrets" {
  description = "Every Secret synced from the vault: name (same in the vault and in Kubernetes), namespace, data key (secretKey) and Secret type."
  value       = local.external_secrets
}
