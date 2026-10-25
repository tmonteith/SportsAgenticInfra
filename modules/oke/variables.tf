variable "tenancy_ocid" {
  description = "The Tenancy OCID."
  type        = string
}

variable "compartment_id" {
  description = "Compartment OCID where the OKE cluster will be created."
  type        = string
}

variable "prefix" {
  description = "Resource naming prefix."
  type        = string
  default     = "sportsagentic"
}

variable "vcn_id" {
  description = "OCID of the VCN."
  type        = string
}

variable "k8s_api_subnet_id" {
  description = "Subnet OCID for the Kubernetes API endpoint."
  type        = string
}

variable "lb_subnet_id" {
  description = "Subnet OCID for the public Load Balancer."
  type        = string
}

variable "nodes_subnet_id" {
  description = "Subnet OCID for the private worker nodes."
  type        = string
}

variable "cluster_type" {
  description = "The type of OKE cluster ('BASIC_CLUSTER' or 'ENHANCED_CLUSTER')."
  type        = string
  default     = "BASIC_CLUSTER"
}

variable "k8s_version" {
  description = "Kubernetes version for OKE cluster and node pools."
  type        = string
  default     = "v1.34.0"
}

variable "node_shape" {
  description = "Compute shape for OKE worker nodes."
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "node_fault_domains" {
  description = "Optional list of fault domains for worker node placement (e.g. ['FAULT-DOMAIN-1', 'FAULT-DOMAIN-2', 'FAULT-DOMAIN-3'])."
  type        = list(string)
  default     = null
}

variable "services_pool_size" {
  description = "Number of worker nodes in the services pool."
  type        = number
  default     = 1
}

variable "services_pool_ocpus" {
  description = "OCPUs per node in the services pool."
  type        = number
  default     = 2
}

variable "services_pool_memory_in_gbs" {
  description = "Memory in GB per node in the services pool."
  type        = number
  default     = 12
}

variable "model_pool_size" {
  description = "Number of worker nodes in the model pool (defaults to 0 until Phase A-4)."
  type        = number
  default     = 0
}

variable "model_pool_ocpus" {
  description = "OCPUs per node in the model pool."
  type        = number
  default     = 4
}

variable "model_pool_memory_in_gbs" {
  description = "Memory in GB per node in the model pool."
  type        = number
  default     = 24
}

variable "ssh_public_key" {
  description = "Optional SSH public key for worker nodes."
  type        = string
  default     = ""
}

variable "node_image_id" {
  description = "Optional custom image OCID for worker nodes. If omitted, discovered dynamically."
  type        = string
  default     = ""
}
