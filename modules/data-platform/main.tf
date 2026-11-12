# Data platform on OKE: namespace "data", workload service accounts and RBAC, OCIR
# repositories for the lakehouse images, Strimzi + Kafka (kafka.tf), Airflow
# (airflow.tf) and the extractor and poller (ingest.tf). Names below come from the
# lakehouse build plan's shared contracts.

locals {
  namespace = "data"

  # Helm values files and local charts live next to the other Kubernetes manifests.
  k8s_dir = "${path.module}/../../k8s/data"

  kafka_cluster_name = "sa-kafka"
  kafka_bootstrap    = "${local.kafka_cluster_name}-kafka-bootstrap.${local.namespace}:9092"
  iceberg_catalog    = "sa_catalog"

  # GCP key contract: Secret gcp-key-<workload>, file mounted at /var/secrets/gcp/key.json.
  gcp_key_mount_path = "/var/secrets/gcp"
  gcp_key_file       = "${local.gcp_key_mount_path}/key.json"

  # Only airflow talks to the Kubernetes API (KubernetesPodOperator). The extractor and
  # the drain pod call GCP with their own keys and get no API token.
  service_accounts = {
    "extractor"   = { automount_token = false }
    "spark-drain" = { automount_token = false }
    "airflow"     = { automount_token = true }
  }

  ocir_repositories = toset(["extractor", "poller", "spark-drain"])

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# 1. Namespace
resource "kubernetes_namespace_v1" "data" {
  metadata {
    name = local.namespace
    labels = {
      "app.kubernetes.io/name"             = local.namespace
      "app.kubernetes.io/part-of"          = "sportsagentic"
      "pod-security.kubernetes.io/enforce" = "baseline"
    }
  }
}

# 2. Workload service accounts. Each references the OCIR pull secret by name so pods
# that use them can pull private images once that Secret exists in this namespace.
resource "kubernetes_service_account_v1" "workload" {
  for_each = local.service_accounts

  metadata {
    name      = each.key
    namespace = kubernetes_namespace_v1.data.metadata[0].name
    labels = {
      "app.kubernetes.io/component" = each.key
      "app.kubernetes.io/part-of"   = "sportsagentic"
    }
  }

  automount_service_account_token = each.value.automount_token

  image_pull_secret {
    name = var.image_pull_secret_name
  }
}

# 3. Namespace-scoped RBAC for Airflow's KubernetesPodOperator: run and clean up pods,
# stream their logs, read events. No exec, no secrets, nothing cluster-wide.
resource "kubernetes_role_v1" "airflow_pod_launcher" {
  metadata {
    name      = "airflow-pod-launcher"
    namespace = kubernetes_namespace_v1.data.metadata[0].name
    labels = {
      "app.kubernetes.io/component" = "airflow"
      "app.kubernetes.io/part-of"   = "sportsagentic"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["create", "get", "list", "watch", "patch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding_v1" "airflow_pod_launcher" {
  metadata {
    name      = "airflow-pod-launcher"
    namespace = kubernetes_namespace_v1.data.metadata[0].name
    labels = {
      "app.kubernetes.io/component" = "airflow"
      "app.kubernetes.io/part-of"   = "sportsagentic"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.airflow_pod_launcher.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.workload["airflow"].metadata[0].name
    namespace = kubernetes_namespace_v1.data.metadata[0].name
  }
}

# 4. Private OCIR repositories for the lakehouse images (multi-arch builds pushed later).
resource "oci_artifacts_container_repository" "data" {
  for_each = local.ocir_repositories

  compartment_id = var.compartment_id
  display_name   = "sportsagentic/${each.key}"
  is_public      = false
  is_immutable   = false

  freeform_tags = local.freeform_tags
}
