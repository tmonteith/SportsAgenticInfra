locals {
  domain_prefix    = var.identity_domain_name != "" ? "'${var.identity_domain_name}'/" : ""
  mcp_nodes_dg_ref = "${local.domain_prefix}'${var.mcp_nodes_dynamic_group_name}'"
}

# 1. OCIR Container Repositories
resource "oci_artifacts_container_repository" "mcp_server" {
  compartment_id = var.compartment_id
  display_name   = "sportsagentic/mcp-server"
  is_public      = false
  is_immutable   = false

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

resource "oci_artifacts_container_repository" "agent_model" {
  compartment_id = var.compartment_id
  display_name   = "sportsagentic/agent-model"
  is_public      = false
  is_immutable   = false

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# 2. OCI NoSQL Table
resource "oci_nosql_table" "cfb" {
  compartment_id = var.compartment_id
  name           = var.nosql_table_name
  ddl_statement  = "CREATE TABLE IF NOT EXISTS ${var.nosql_table_name} (id STRING, entity_type STRING, season INTEGER, week INTEGER, data JSON, created_at TIMESTAMP, updated_at TIMESTAMP, PRIMARY KEY (SHARD(entity_type), id))"

  table_limits {
    max_read_units     = var.nosql_max_read_units
    max_write_units    = var.nosql_max_write_units
    max_storage_in_gbs = var.nosql_max_storage_in_gbs
    capacity_mode      = "PROVISIONED"
  }

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# 3. Scoped IAM Policy for NoSQL Table Read Access
resource "oci_identity_policy" "nosql_mcp_access" {
  compartment_id = var.tenancy_ocid
  name           = "${var.prefix}-nosql-mcp-policy"
  description    = "Grants read access to NoSQL tables/rows strictly to the MCP workload"

  statements = concat(
    [
      "Allow dynamic-group ${local.mcp_nodes_dg_ref} to read nosql-tables in compartment ${var.compartment_name}",
      "Allow dynamic-group ${local.mcp_nodes_dg_ref} to read nosql-rows in compartment ${var.compartment_name}"
    ],
    var.enable_oke_workload_identity && var.cluster_id != "" ? [
      "Allow any-user to read nosql-tables in compartment ${var.compartment_name} where all { request.principal.type = 'workload', request.principal.cluster_id = '${var.cluster_id}', request.principal.namespace = 'sportsagentic', request.principal.service_account = 'mcp-server-sa' }",
      "Allow any-user to read nosql-rows in compartment ${var.compartment_name} where all { request.principal.type = 'workload', request.principal.cluster_id = '${var.cluster_id}', request.principal.namespace = 'sportsagentic', request.principal.service_account = 'mcp-server-sa' }"
    ] : []
  )

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# 4. Authoritative OCI Public DNS Zone
resource "oci_dns_zone" "main" {
  compartment_id = var.compartment_id
  name           = var.domain_name
  zone_type      = "PRIMARY"

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# 5. Kubernetes Namespaces
resource "kubernetes_namespace_v1" "sportsagentic" {
  metadata {
    name = "sportsagentic"
    labels = {
      "app.kubernetes.io/name"             = "sportsagentic"
      "app.kubernetes.io/part-of"          = "sportsagentic"
      "pod-security.kubernetes.io/enforce" = "baseline"
    }
  }
}

resource "kubernetes_namespace_v1" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
    labels = {
      "app.kubernetes.io/name" = "ingress-nginx"
    }
  }
}

resource "kubernetes_namespace_v1" "cert_manager" {
  metadata {
    name = "cert-manager"
    labels = {
      "app.kubernetes.io/name" = "cert-manager"
    }
  }
}

# 6. Scoped Kubernetes ServiceAccounts & RBAC
# A. MCP Server Workload Identity ServiceAccount
resource "kubernetes_service_account_v1" "mcp_server" {
  metadata {
    name      = "mcp-server-sa"
    namespace = kubernetes_namespace_v1.sportsagentic.metadata[0].name
    labels = {
      "app.kubernetes.io/component" = "mcp-server"
      "app.kubernetes.io/part-of"   = "sportsagentic"
    }
  }
}

# B. App Pipeline Deployer ServiceAccount & Namespace-Scoped RBAC
resource "kubernetes_service_account_v1" "app_deployer" {
  metadata {
    name      = "app-deployer-sa"
    namespace = kubernetes_namespace_v1.sportsagentic.metadata[0].name
    labels = {
      "app.kubernetes.io/component" = "deployer"
      "app.kubernetes.io/part-of"   = "sportsagentic"
    }
  }
}

resource "kubernetes_role_v1" "app_deployer" {
  metadata {
    name      = "app-deployer-role"
    namespace = kubernetes_namespace_v1.sportsagentic.metadata[0].name
  }

  rule {
    api_groups = ["", "apps", "networking.k8s.io", "autoscaling"]
    resources = [
      "deployments",
      "services",
      "configmaps",
      "secrets",
      "ingresses",
      "horizontalpodautoscalers",
      "pods",
      "pods/log",
      "events"
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding_v1" "app_deployer" {
  metadata {
    name      = "app-deployer-binding"
    namespace = kubernetes_namespace_v1.sportsagentic.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.app_deployer.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.app_deployer.metadata[0].name
    namespace = kubernetes_namespace_v1.sportsagentic.metadata[0].name
  }
}

# 7. Ingress-Nginx Controller via Helm
resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.11.3"
  namespace  = kubernetes_namespace_v1.ingress_nginx.metadata[0].name

  values = [
    <<-EOT
    controller:
      service:
        annotations:
          oci.oraclecloud.com/load-balancer-type: "lb"
          service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
          service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
          service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"
          service.beta.kubernetes.io/oci-load-balancer-subnet1: "${var.lb_subnet_id}"
      metrics:
        enabled: true
    EOT
  ]
}

# 8. Cert-Manager via Helm
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.16.1"
  namespace  = kubernetes_namespace_v1.cert_manager.metadata[0].name

  set = [
    {
      name  = "installCRDs"
      value = "true"
    }
  ]
}

# 9. ClusterIssuer for Let's Encrypt
resource "helm_release" "cluster_issuer" {
  name       = "cluster-issuer"
  chart      = "${path.module}/charts/cluster-issuer"
  namespace  = kubernetes_namespace_v1.cert_manager.metadata[0].name
  depends_on = [helm_release.cert_manager]

  set = [
    {
      name  = "email"
      value = var.letsencrypt_email
    },
    {
      name  = "domain"
      value = var.domain_name
    }
  ]
}
