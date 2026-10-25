# 1. Discover Availability Domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

locals {
  is_arm       = length(regexall(".*A1.*", var.node_shape)) > 0
  os_arch      = local.is_arm ? "AARCH64" : "X86_64"
  arch_pattern = local.is_arm ? ".*aarch64.*" : ".*(x86_64|amd64).*"
}

# 2. Discover OKE-ready node images (Architecture-specific & version-specific)
data "oci_containerengine_node_pool_option" "oke" {
  node_pool_option_id   = "all"
  compartment_id        = var.compartment_id
  node_pool_k8s_version = startswith(var.k8s_version, "v") ? var.k8s_version : "v${var.k8s_version}"
  node_pool_os_arch     = local.os_arch
}

data "oci_containerengine_node_pool_option" "oke_all" {
  node_pool_option_id = "all"
  compartment_id      = var.compartment_id
}

locals {
  k8s_version_clean = replace(var.k8s_version, "v", "")

  combined_sources = concat(
    try(data.oci_containerengine_node_pool_option.oke.sources, []),
    try(data.oci_containerengine_node_pool_option.oke_all.sources, [])
  )

  # 1. Exact match for target architecture AND requested k8s version (e.g. 1.34.0)
  sources_matching_both = [
    for source in local.combined_sources :
    source.image_id
    if length(regexall(local.arch_pattern, lower(source.source_name))) > 0 &&
    length(regexall(".*${local.k8s_version_clean}.*", source.source_name)) > 0
  ]

  # 2. Match for target architecture only
  sources_matching_arch = [
    for source in local.combined_sources :
    source.image_id
    if length(regexall(local.arch_pattern, lower(source.source_name))) > 0
  ]

  # Safely resolve image without index out of bounds
  node_image_id = var.node_image_id != "" ? var.node_image_id : try(
    local.sources_matching_both[0],
    try(
      local.sources_matching_arch[0],
      try(local.combined_sources[0].image_id, "")
    )
  )
}

# 3. OKE Cluster (Control Plane)
resource "oci_containerengine_cluster" "main" {
  compartment_id     = var.compartment_id
  kubernetes_version = var.k8s_version
  name               = "${var.prefix}-oke-cluster"
  vcn_id             = var.vcn_id
  type               = var.cluster_type

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = var.k8s_api_subnet_id
  }

  cluster_pod_network_options {
    cni_type = "FLANNEL_OVERLAY"
  }

  options {
    service_lb_subnet_ids = [var.lb_subnet_id]

    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }

    admission_controller_options {
      is_pod_security_policy_enabled = false
    }

    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
  }

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# 4. Single Worker Node Pool (Always Free ARM VM.Standard.A1.Flex: 1 node, 4 OCPUs, 24 GB RAM)
resource "oci_containerengine_node_pool" "model" {
  cluster_id         = oci_containerengine_cluster.main.id
  compartment_id     = var.compartment_id
  kubernetes_version = var.k8s_version
  name               = "model-pool"
  node_shape         = var.node_shape

  node_shape_config {
    ocpus         = var.model_pool_ocpus
    memory_in_gbs = var.model_pool_memory_in_gbs
  }

  node_source_details {
    image_id    = local.node_image_id
    source_type = "IMAGE"
  }

  node_config_details {
    dynamic "placement_configs" {
      for_each = data.oci_identity_availability_domains.ads.availability_domains
      content {
        availability_domain = placement_configs.value.name
        subnet_id           = var.nodes_subnet_id
        fault_domains       = var.node_fault_domains
      }
    }
    size = var.model_pool_size

    freeform_tags = {
      "node_pool" = "model"
      "Project"   = "SportsAgentic"
      "ManagedBy" = "OpenTofu"
    }
  }

  initial_node_labels {
    key   = "workload-role"
    value = "model"
  }

  initial_node_labels {
    key   = "pool"
    value = "model"
  }

  node_metadata = {
    user_data = base64encode(<<-EOT
      #!/bin/bash
      curl --fail -H "Authorization: Bearer Oracle" -L0 http://169.254.169.254/opc/v2/instance/metadata/oke_init_script | base64 --decode >/var/run/oke-init.sh
      bash /var/run/oke-init.sh --kubelet-extra-args "--register-with-taints=workload-role=model:NoSchedule"
    EOT
    )
  }

  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : null

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# 5. Cluster Kubeconfig Data Source
data "oci_containerengine_cluster_kube_config" "kubeconfig" {
  cluster_id = oci_containerengine_cluster.main.id
  endpoint   = "PUBLIC_ENDPOINT"
}
