variable "tenancy_ocid" {
  description = "The Tenancy OCID."
  type        = string
}

variable "user_ocid" {
  description = "The User OCID for OCI API authentication."
  type        = string
  default     = null
}

variable "fingerprint" {
  description = "The fingerprint of the OCI API private key."
  type        = string
  default     = null
}

variable "private_key" {
  description = "The PEM contents of the OCI API private key."
  type        = string
  default     = null
  sensitive   = true
}

variable "private_key_path" {
  description = "Path to the OCI API private key file."
  type        = string
  default     = null
}

variable "config_file_profile" {
  description = "The profile name to use from ~/.oci/config."
  type        = string
  default     = null
}

variable "region" {
  description = "The OCI region."
  type        = string
  default     = "us-ashburn-1"
}

variable "compartment_id" {
  description = "OCID of the dedicated sportsagentic compartment created by bootstrap."
  type        = string
}

variable "compartment_name" {
  description = "Name of the dedicated compartment."
  type        = string
  default     = "sportsagentic"
}

variable "identity_domain_name" {
  description = "Identity Domain name (e.g. 'Default'). Leave empty for classic IAM."
  type        = string
  default     = "Default"
}

variable "prefix" {
  description = "Prefix for naming resources."
  type        = string
  default     = "sportsagentic"
}

variable "cluster_type" {
  description = "OKE cluster type ('BASIC_CLUSTER' or 'ENHANCED_CLUSTER')."
  type        = string
  default     = "BASIC_CLUSTER"
}

variable "k8s_version" {
  description = "Kubernetes version for OKE cluster and node pools."
  type        = string
  default     = "v1.34.0"
}

variable "domain_name" {
  description = "Authoritative domain name for SportsAgentic."
  type        = string
  default     = "sportagentic.dev"
}

variable "services_pool_size" {
  description = "Number of worker nodes for the services pool."
  type        = number
  default     = 1
}

variable "services_pool_ocpus" {
  description = "OCPUs per node in services pool."
  type        = number
  default     = 2
}

variable "services_pool_memory_in_gbs" {
  description = "Memory in GB per node in services pool."
  type        = number
  default     = 12
}

variable "model_pool_size" {
  description = "Number of worker nodes in model pool (sits at 0 until Phase A-4)."
  type        = number
  default     = 0
}

variable "model_pool_ocpus" {
  description = "OCPUs per node in model pool."
  type        = number
  default     = 4
}

variable "model_pool_memory_in_gbs" {
  description = "Memory in GB per node in model pool."
  type        = number
  default     = 24
}

variable "ssh_public_key" {
  description = "Optional SSH public key for compute instances."
  type        = string
  default     = ""
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate notices."
  type        = string
  default     = "admin@sportagentic.dev"
}

variable "email" {
  description = "Email of the user apply terraform"
  type        = string
  default     = null
}
