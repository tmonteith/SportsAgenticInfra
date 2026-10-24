locals {
  domain_prefix    = (var.identity_domain_name != "" && lower(var.identity_domain_name) != "default") ? "'${var.identity_domain_name}'/" : ""
  oke_nodes_dg_ref = "${local.domain_prefix}${oci_identity_dynamic_group.oke_nodes.name}"
  mcp_nodes_dg_ref = "${local.domain_prefix}${oci_identity_dynamic_group.mcp_nodes.name}"
  app_ci_group_ref = "${local.domain_prefix}${oci_identity_group.app_ci_group.name}"
}

# 1. Dynamic Group for OKE Worker Nodes (for joining cluster and pulling OCIR images)
resource "oci_identity_dynamic_group" "oke_nodes" {
  compartment_id = var.tenancy_ocid
  name           = "${var.prefix}-oke-nodes-dg"
  description    = "Dynamic group for all worker nodes in the SportsAgentic OKE cluster"
  matching_rule  = "instance.compartment.id = '${var.compartment_id}'"

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# 2. Dynamic Group for MCP Services Pool Nodes (for scoped NoSQL access in Basic Cluster)
resource "oci_identity_dynamic_group" "mcp_nodes" {
  compartment_id = var.tenancy_ocid
  name           = "${var.prefix}-mcp-nodes-dg"
  description    = "Dynamic group matching services pool instances for scoped NoSQL access"
  matching_rule  = "ALL {instance.compartment.id = '${var.compartment_id}', tag.node_pool.value = 'services'}"

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# 3. Policy for Worker Nodes: Joining Cluster, OCIR Pull, Subnet Usage
resource "oci_identity_policy" "oke_nodes" {
  compartment_id = var.tenancy_ocid
  name           = "${var.prefix}-oke-nodes-policy"
  description    = "Allows OKE worker nodes to join the cluster, use networking, and pull container images from OCIR"

  statements = [
    "Allow dynamic-group ${local.oke_nodes_dg_ref} to manage instance-family in compartment ${var.compartment_name}",
    "Allow dynamic-group ${local.oke_nodes_dg_ref} to use subnets in compartment ${var.compartment_name}",
    "Allow dynamic-group ${local.oke_nodes_dg_ref} to read repos in compartment ${var.compartment_name}",
    "Allow dynamic-group ${local.oke_nodes_dg_ref} to {CLUSTER_JOIN} in compartment ${var.compartment_name}"
  ]

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# 4. App CI Service Account for Application Deployment Pipeline
resource "oci_identity_group" "app_ci_group" {
  compartment_id = var.tenancy_ocid
  name           = "${var.prefix}-app-ci-group"
  description    = "Dedicated IAM group for SportsAgentic app repository CI/CD pipelines"

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

resource "oci_identity_user" "app_ci_user" {
  compartment_id = var.tenancy_ocid
  name           = "${var.prefix}-app-ci"
  description    = "Service account for SportsAgentic app deployment pipeline (OCIR push & OKE deploy)"

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

resource "oci_identity_user_group_membership" "app_ci_membership" {
  group_id = oci_identity_group.app_ci_group.id
  user_id  = oci_identity_user.app_ci_user.id
}

resource "oci_identity_policy" "app_ci_policy" {
  compartment_id = var.tenancy_ocid
  name           = "${var.prefix}-app-ci-policy"
  description    = "Grants the application pipeline permissions to push images to OCIR and access OKE"

  statements = [
    "Allow group ${local.app_ci_group_ref} to manage repos in compartment ${var.compartment_name}",
    "Allow group ${local.app_ci_group_ref} to use clusters in compartment ${var.compartment_name}",
    "Allow group ${local.app_ci_group_ref} to read clusters in compartment ${var.compartment_name}"
  ]

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

