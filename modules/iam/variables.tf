variable "tenancy_ocid" {
  description = "The Tenancy OCID."
  type        = string
}

variable "compartment_id" {
  description = "Compartment OCID for SportsAgentic resources."
  type        = string
}

variable "compartment_name" {
  description = "Name of the SportsAgentic compartment."
  type        = string
  default     = "sportsagentic"
}

variable "identity_domain_name" {
  description = "Identity domain name (e.g. 'Default'). Leave empty for classic IAM."
  type        = string
  default     = "Default"
}

variable "prefix" {
  description = "Prefix for naming IAM resources."
  type        = string
  default     = "sportsagentic"
}

variable "email" {
  description = "Email of the user apply terraform"
  type        = string
  default     = null
}
