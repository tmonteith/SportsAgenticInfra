variable "tenancy_ocid" {
  description = "Tenancy OCID for creating the tenancy-level IAM policy."
  type        = string
}

variable "compartment_id" {
  description = "Compartment OCID where the vault and master key reside."
  type        = string
}

variable "compartment_name" {
  description = "Name of the compartment (used in IAM policy statements)."
  type        = string
  default     = "sportsagentic"
}

variable "identity_domain_name" {
  description = "Identity Domain name (e.g. 'Default'). Leave empty for classic IAM."
  type        = string
  default     = "Default"
}

variable "prefix" {
  description = "Resource prefix."
  type        = string
  default     = "sportsagentic"
}

variable "region" {
  description = "OCI region of the vault, used by the External Secrets ClusterSecretStore (e.g. us-chicago-1)."
  type        = string
}

variable "reader_dynamic_group_name" {
  description = "Dynamic group matching the OKE worker nodes. External Secrets runs on those nodes and reads the vault as their instance principal."
  type        = string
}

variable "data_namespace" {
  description = "Kubernetes namespace of the data platform (extractor, spark-drain, airflow). Created elsewhere; pass the creating module's output so the dependency is explicit."
  type        = string
}

variable "app_namespace" {
  description = "Kubernetes namespace of the SportsAgentic app (MCP server). Created elsewhere; pass the creating module's output so the dependency is explicit."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace created for the External Secrets Operator."
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_chart_version" {
  description = "Pinned version of the external-secrets Helm chart (images are multi-arch: linux/amd64 and linux/arm64)."
  type        = string
  default     = "2.14.0"
}

variable "cluster_secret_store_name" {
  description = "Name of the ClusterSecretStore that points at the OCI Vault."
  type        = string
  default     = "oci-vault"
}

variable "refresh_interval" {
  description = "How often External Secrets re-reads each vault secret. After a key rotation the Kubernetes Secret updates within this interval."
  type        = string
  default     = "1h"
}
