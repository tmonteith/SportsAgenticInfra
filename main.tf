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

# 2. IAM Module (Dynamic Groups and Policies for OKE worker nodes)
module "iam" {
  source = "./modules/iam"

  tenancy_ocid         = var.tenancy_ocid
  compartment_id       = var.compartment_id
  compartment_name     = var.compartment_name
  identity_domain_name = var.identity_domain_name
  prefix               = var.prefix
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
  node_image_id            = var.node_image_id
  node_fault_domains       = var.node_fault_domains
  node_availability_domain = var.node_availability_domain
  model_pool_size          = var.model_pool_size
  model_pool_ocpus         = var.model_pool_ocpus
  model_pool_memory_in_gbs = var.model_pool_memory_in_gbs
  ssh_public_key           = var.ssh_public_key

  # No depends_on = [module.iam] here. A module-level depends_on defers every data
  # source in this module, including the kubeconfig, whenever IAM has pending changes.
  # The kubernetes and helm providers are configured from that kubeconfig, so a
  # deferred read leaves them pointing at localhost and the whole plan fails.
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
  ingress_public_ip            = var.ingress_public_ip
  letsencrypt_email            = var.letsencrypt_email

  depends_on = [module.oke]
}

# 5. Data Platform Module (namespace data, Strimzi Kafka, Airflow, lakehouse OCIR repos, ingest)
module "data_platform" {
  source = "./modules/data-platform"

  compartment_id = var.compartment_id
  gcp_project_id = var.gcp_project_id

  # Extractor and poller (k8s/data/ingest), installed once their images are pushed.
  ingest_image_tag = var.ingest_image_tag
  ocir_namespace   = data.oci_objectstorage_namespace.ns.namespace

  depends_on = [module.oke]
}

# 6. Secrets Module (OCI Vault, External Secrets Operator, GCP key ExternalSecrets)
module "secrets" {
  source = "./modules/secrets"

  tenancy_ocid         = var.tenancy_ocid
  compartment_id       = var.compartment_id
  compartment_name     = var.compartment_name
  identity_domain_name = var.identity_domain_name
  prefix               = var.prefix
  region               = var.region

  # Every worker node in the compartment. The MCP services group matches no node:
  # its rule needs node_pool = 'services' and the only pool is tagged 'model'.
  reader_dynamic_group_name = module.iam.oke_nodes_dynamic_group_name

  # Module outputs, so the namespaces exist before the ExternalSecrets in them.
  app_namespace  = module.platform.app_namespace
  data_namespace = module.data_platform.namespace
}
