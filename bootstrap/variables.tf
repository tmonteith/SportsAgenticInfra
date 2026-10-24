variable "tenancy_ocid" {
  description = "The OCID of the root tenancy."
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
  description = "The OCI region to provision resources in (e.g. us-ashburn-1, us-phoenix-1)."
  type        = string
  default     = "us-ashburn-1"
}

variable "identity_domain_name" {
  description = "The IAM Identity Domain name (e.g. 'Default'). Leave empty for classic OCI tenancies."
  type        = string
  default     = "Default"
}

variable "compartment_name" {
  description = "The name of the dedicated compartment to create for SportsAgentic."
  type        = string
  default     = "sportsagentic"
}

variable "compartment_description" {
  description = "Description for the dedicated SportsAgentic compartment."
  type        = string
  default     = "Compartment for SportsAgentic infrastructure, OKE cluster, and data storage."
}

variable "tfstate_bucket_name" {
  description = "Name of the private Object Storage bucket for OpenTofu state."
  type        = string
  default     = "sportsagentic-tfstate"
}
