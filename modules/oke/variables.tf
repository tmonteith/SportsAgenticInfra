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
    condition     = contains(["VM.Standard.A1.Flex", "VM.Standard.A2.Flex", "VM.Standard.E5.Flex", "VM.Standard.E4.Flex", "VM.Standard3.Flex"], var.node_shape)
    error_message = "Node shape must be a supported flexible compute shape (e.g. VM.Standard.A1.Flex, VM.Standard.E5.Flex)."
  }
}

variable "node_fault_domains" {
  description = "Optional list of fault domains for worker node placement (e.g. ['FAULT-DOMAIN-1', 'FAULT-DOMAIN-2', 'FAULT-DOMAIN-3'])."
  type        = list(string)
  default     = null
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
  description = "OCPUs per node in the single node pool."
  type        = number
  default     = 4

  validation {
    condition     = var.model_pool_ocpus >= 1 && var.model_pool_ocpus <= 64
    error_message = "OCPUs must be between 1 and 64."
  }
}

variable "model_pool_memory_in_gbs" {
  description = "Memory in GB per node in the single node pool."
  type        = number
  default     = 24

  validation {
    condition     = var.model_pool_memory_in_gbs >= 1 && var.model_pool_memory_in_gbs <= 512
    error_message = "Memory must be between 1 and 512 GB."
  }
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
