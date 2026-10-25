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

  validation {
    condition     = var.cluster_type == "BASIC_CLUSTER"
    error_message = "Cluster type must be BASIC_CLUSTER."
  }
}

variable "k8s_version" {
  description = "Kubernetes version for OKE cluster and node pools."
  type        = string
  default     = "v1.34.10"
}

variable "node_shape" {
  description = "Compute shape for OKE worker nodes."
  type        = string
  default     = "VM.Standard.A1.Flex"

  validation {
    condition     = var.node_shape == "VM.Standard.A1.Flex"
    error_message = "Node shape must be VM.Standard.A1.Flex for Always Free ARM compute."
  }
}

variable "node_fault_domains" {
  description = "Optional list of fault domains for worker node placement (e.g. ['FAULT-DOMAIN-1', 'FAULT-DOMAIN-2', 'FAULT-DOMAIN-3'])."
  type        = list(string)
  default     = null
}

variable "domain_name" {
  description = "Authoritative domain name for SportsAgentic."
  type        = string
  default     = "sportagentic.dev"
}

variable "model_pool_size" {
  description = "Number of worker nodes in the single node pool (max 1 on Always Free tier)."
  type        = number
  default     = 1

  validation {
    condition     = var.model_pool_size >= 0 && var.model_pool_size <= 1 && floor(var.model_pool_size) == var.model_pool_size
    error_message = "Node count must be an integer between 0 and 1 (cannot exceed 1 node on Always Free tier)."
  }
}

variable "model_pool_ocpus" {
  description = "OCPUs per node in the single node pool (max 4 on Always Free tier)."
  type        = number
  default     = 4

  validation {
    condition     = var.model_pool_ocpus >= 1 && var.model_pool_ocpus <= 4
    error_message = "OCPUs must be between 1 and 4 to stay within OCI Always Free Ampere A1 limits (max 4 OCPUs)."
  }
}

variable "model_pool_memory_in_gbs" {
  description = "Memory in GB per node in the single node pool (max 24 GB on Always Free tier)."
  type        = number
  default     = 24

  validation {
    condition     = var.model_pool_memory_in_gbs >= 1 && var.model_pool_memory_in_gbs <= 24
    error_message = "Memory must be between 1 and 24 GB to stay within OCI Always Free Ampere A1 limits (max 24 GB)."
  }
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
