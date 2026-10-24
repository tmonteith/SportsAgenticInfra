variable "compartment_id" {
  description = "Compartment OCID where platform resources reside."
  type        = string
}

variable "tenancy_ocid" {
  description = "Tenancy OCID for creating tenancy-level IAM policies."
  type        = string
}

variable "compartment_name" {
  description = "Name of the compartment."
  type        = string
  default     = "sportsagentic"
}

variable "identity_domain_name" {
  description = "Identity Domain name (e.g. 'Default')."
  type        = string
  default     = "Default"
}

variable "cluster_id" {
  description = "OCID of the OKE cluster."
  type        = string
  default     = ""
}

variable "mcp_nodes_dynamic_group_name" {
  description = "Name of the Dynamic Group matching MCP services pool instances."
  type        = string
  default     = "sportsagentic-mcp-nodes-dg"
}

variable "enable_oke_workload_identity" {
  description = "Whether to emit native OKE Workload Identity policy statements."
  type        = bool
  default     = false
}

variable "prefix" {
  description = "Resource prefix."
  type        = string
  default     = "sportsagentic"
}

variable "lb_subnet_id" {
  description = "Subnet OCID for the ingress Load Balancer."
  type        = string
}

variable "domain_name" {
  description = "Domain name for the public DNS zone and TLS certificates."
  type        = string
  default     = "sportagentic.dev"
}

variable "nosql_table_name" {
  description = "Name of the NoSQL table for caching and storing sports data."
  type        = string
  default     = "sportsagentic_cfb"
}

variable "nosql_max_read_units" {
  description = "Maximum sustained read throughput units for the NoSQL table."
  type        = number
  default     = 50
}

variable "nosql_max_write_units" {
  description = "Maximum sustained write throughput units for the NoSQL table."
  type        = number
  default     = 50
}

variable "nosql_max_storage_in_gbs" {
  description = "Maximum storage size in GBs for the NoSQL table."
  type        = number
  default     = 25
}

variable "letsencrypt_email" {
  description = "Contact email for Let's Encrypt certificate expiry notices."
  type        = string
  default     = "admin@sportagentic.dev"
}
