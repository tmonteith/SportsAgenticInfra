variable "compartment_id" {
  description = "Compartment OCID where network resources will be provisioned."
  type        = string
}

variable "prefix" {
  description = "Resource prefix for naming."
  type        = string
  default     = "sportsagentic"
}

variable "vcn_cidr" {
  description = "CIDR block for the VCN."
  type        = string
  default     = "10.0.0.0/16"
}

variable "k8s_api_subnet_cidr" {
  description = "CIDR block for the OKE Kubernetes API endpoint subnet."
  type        = string
  default     = "10.0.0.0/28"
}

variable "lb_subnet_cidr" {
  description = "CIDR block for the public Load Balancer subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "nodes_subnet_cidr" {
  description = "CIDR block for the private worker nodes subnet."
  type        = string
  default     = "10.0.10.0/24"
}

variable "k8s_api_allowed_cidrs" {
  description = "Allowed CIDR blocks for accessing the OKE Kubernetes API endpoint."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
