# Fetch Object Storage Namespace for Tenancy
data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.tenancy_ocid
}

# 1. Network Module (VCN, Subnets, Gateways, Route Tables, Security Lists)
module "network" {
  source = "./modules/network"

  compartment_id = var.compartment_id
  prefix         = var.prefix
}

# 2. IAM Module (Dynamic Groups, Policies for OKE, and App Deployment)
module "iam" {
  source = "./modules/iam"

  tenancy_ocid         = var.tenancy_ocid
  compartment_id       = var.compartment_id
  compartment_name     = var.compartment_name
  identity_domain_name = var.identity_domain_name
  prefix               = var.prefix
  email                = var.email
}

# 3. OKE Cluster Module (Control Plane + Services Pool + Model Pool @ 0)
module "oke" {
  source = "./modules/oke"

  tenancy_ocid             = var.tenancy_ocid
  compartment_id           = var.compartment_id
  prefix                   = var.prefix
  vcn_id                   = module.network.vcn_id
  k8s_api_subnet_id        = module.network.k8s_api_subnet_id
  lb_subnet_id             = module.network.lb_subnet_id
  nodes_subnet_id          = module.network.nodes_subnet_id
  cluster_type             = var.cluster_type
  k8s_version              = var.k8s_version
  node_shape               = var.node_shape
  node_fault_domains       = var.node_fault_domains
  model_pool_size          = var.model_pool_size
  model_pool_ocpus         = var.model_pool_ocpus
  model_pool_memory_in_gbs = var.model_pool_memory_in_gbs
  ssh_public_key           = var.ssh_public_key

  depends_on = [module.iam]
}

# 4. Platform Module (OCIR, NoSQL, NoSQL IAM Policy, OCI DNS, Ingress-Nginx, cert-manager, K8s RBAC)
module "platform" {
  source = "./modules/platform"

  tenancy_ocid                 = var.tenancy_ocid
  compartment_id               = var.compartment_id
  compartment_name             = var.compartment_name
  identity_domain_name         = var.identity_domain_name
  cluster_id                   = module.oke.cluster_id
  mcp_nodes_dynamic_group_name = module.iam.mcp_nodes_dynamic_group_name
  enable_oke_workload_identity = var.cluster_type == "ENHANCED_CLUSTER"
  prefix                       = var.prefix
  lb_subnet_id                 = module.network.lb_subnet_id
  domain_name                  = var.domain_name
  letsencrypt_email            = var.letsencrypt_email

  depends_on = [module.oke]
}
