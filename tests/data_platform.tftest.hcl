mock_provider "oci" {
  mock_data "oci_identity_availability_domains" {
    defaults = {
      availability_domains = [
        {
          compartment_id = "ocid1.tenancy.oc1..test"
          id             = "ocid1.ad.oc1..test1"
          name           = "Uwhm:US-CHICAGO-1-AD-1"
        }
      ]
    }
  }

  mock_data "oci_containerengine_node_pool_option" {
    defaults = {
      sources = [
        {
          image_id    = "ocid1.image.oc1.ord.amd-test-image"
          source_name = "Oracle-Linux-9.8-2024.08.31-0-OKE-1.34.10-1"
          source_type = "IMAGE"
        }
      ]
    }
  }
}
mock_provider "kubernetes" {}
mock_provider "helm" {}

variables {
  compartment_id = "ocid1.compartment.oc1..test"
  gcp_project_id = "sports-agent-test"
}

run "test_data_platform_module" {
  command = plan

  module {
    source = "./modules/data-platform"
  }

  # Namespace
  assert {
    condition     = kubernetes_namespace_v1.data.metadata[0].name == "data"
    error_message = "Data platform namespace must be data"
  }

  assert {
    condition     = kubernetes_namespace_v1.data.metadata[0].labels["pod-security.kubernetes.io/enforce"] == "baseline"
    error_message = "Namespace data must enforce the baseline pod security standard"
  }

  # Service accounts and RBAC
  assert {
    condition     = toset(keys(kubernetes_service_account_v1.workload)) == toset(["extractor", "spark-drain", "airflow"])
    error_message = "Service accounts must be exactly extractor, spark-drain and airflow"
  }

  assert {
    condition     = alltrue([for sa in kubernetes_service_account_v1.workload : sa.metadata[0].namespace == "data"])
    error_message = "All workload service accounts must live in namespace data"
  }

  assert {
    condition     = !kubernetes_service_account_v1.workload["extractor"].automount_service_account_token && !kubernetes_service_account_v1.workload["spark-drain"].automount_service_account_token
    error_message = "Only the airflow service account may mount a Kubernetes API token"
  }

  assert {
    condition     = kubernetes_role_binding_v1.airflow_pod_launcher.subject[0].name == "airflow" && kubernetes_role_binding_v1.airflow_pod_launcher.role_ref[0].kind == "Role"
    error_message = "The pod launcher Role must be bound (namespace-scoped) to the airflow service account"
  }

  assert {
    condition     = !contains(flatten([for r in kubernetes_role_v1.airflow_pod_launcher.rule : r.resources]), "secrets") && !contains(flatten([for r in kubernetes_role_v1.airflow_pod_launcher.rule : r.resources]), "pods/exec")
    error_message = "The airflow Role must not grant secrets or pods/exec"
  }

  # OCIR
  assert {
    condition     = toset([for r in oci_artifacts_container_repository.data : r.display_name]) == toset(["sportsagentic/extractor", "sportsagentic/poller", "sportsagentic/spark-drain"])
    error_message = "OCIR repositories must be sportsagentic/extractor, sportsagentic/poller and sportsagentic/spark-drain"
  }

  assert {
    condition     = alltrue([for r in oci_artifacts_container_repository.data : !r.is_public])
    error_message = "OCIR repositories must be private"
  }

  # Kafka
  assert {
    condition     = yamldecode(helm_release.kafka.values[0]).clusterName == "sa-kafka" && output.kafka_bootstrap == "sa-kafka-kafka-bootstrap.data:9092"
    error_message = "Kafka cluster must be sa-kafka with bootstrap sa-kafka-kafka-bootstrap.data:9092"
  }

  assert {
    condition     = output.kafka_topics == ["cfb.live_games", "agent.events"]
    error_message = "Kafka topics must be cfb.live_games and agent.events"
  }

  assert {
    condition     = alltrue([for t in yamldecode(helm_release.kafka.values[0]).topics : t.partitions == 1 && t.replicas == 1])
    error_message = "Each topic must have 1 partition and 1 replica"
  }

  assert {
    condition     = yamldecode(helm_release.kafka.values[0]).topicConfig["retention.ms"] == "604800000"
    error_message = "Topic retention must be 7 days"
  }

  assert {
    condition     = output.memory_limits_mib.kafka_broker == 1280 && output.memory_limits_mib.kafka_heap == 768
    error_message = "Kafka must have a 1280Mi memory limit and a 768m heap"
  }

  assert {
    condition     = yamldecode(helm_release.kafka.values[0]).storage.size == "50Gi"
    error_message = "Kafka volume must be 50Gi"
  }

  assert {
    condition     = helm_release.strimzi.version == "1.3.1" && helm_release.airflow.version == "1.22.0"
    error_message = "Strimzi and Airflow chart versions must be pinned"
  }

  # Airflow
  assert {
    condition     = output.memory_limits_mib.airflow_total <= 3072
    error_message = "Airflow memory limits must sum to at most 3 GiB"
  }

  assert {
    condition     = output.memory_limits_mib.airflow_total == 3008
    error_message = "Airflow memory limit total changed; update the budget in docs/data-platform.md"
  }

  assert {
    condition     = yamldecode(helm_release.airflow.values[0]).executor == "LocalExecutor" && !yamldecode(helm_release.airflow.values[0]).triggerer.enabled
    error_message = "Airflow must use LocalExecutor with the triggerer disabled"
  }

  assert {
    condition     = yamldecode(helm_release.airflow.values[1]).scheduler.serviceAccount.name == "airflow" && yamldecode(helm_release.airflow.values[1]).apiServer.serviceAccount.name == "airflow" && yamldecode(helm_release.airflow.values[1]).dagProcessor.serviceAccount.name == "airflow"
    error_message = "Airflow components must run as the airflow service account"
  }

  assert {
    condition = (
      contains(yamldecode(helm_release.airflow.values[1]).env, { name = "KAFKA_BOOTSTRAP", value = "sa-kafka-kafka-bootstrap.data:9092" }) &&
      contains(yamldecode(helm_release.airflow.values[1]).env, { name = "GOOGLE_APPLICATION_CREDENTIALS", value = "/var/secrets/gcp/key.json" }) &&
      contains(yamldecode(helm_release.airflow.values[1]).env, { name = "ICEBERG_CATALOG", value = "sa_catalog" }) &&
      contains(yamldecode(helm_release.airflow.values[1]).env, { name = "GCP_PROJECT", value = "sports-agent-test" })
    )
    error_message = "Airflow must set the shared-contract env vars"
  }

  assert {
    condition     = yamldecode(helm_release.airflow.values[1]).volumes[0].secret.secretName == "gcp-key-airflow" && yamldecode(helm_release.airflow.values[1]).volumes[0].secret.optional
    error_message = "Airflow must mount Secret gcp-key-airflow as an optional volume"
  }

  # No public exposure
  assert {
    condition     = yamldecode(helm_release.airflow.values[0]).apiServer.service.type == "ClusterIP" && !yamldecode(helm_release.airflow.values[0]).ingress.apiServer.enabled && !yamldecode(helm_release.airflow.values[0]).ingress.web.enabled
    error_message = "Airflow API server must be ClusterIP with no Ingress"
  }

  assert {
    condition     = alltrue([for l in yamldecode(helm_release.kafka.values[0]).kafka.listeners : l.type == "internal" && !l.tls])
    error_message = "Kafka must only have internal listeners"
  }

  assert {
    condition     = yamldecode(helm_release.airflow.values[0]).postgresql.primary.persistence.size == "50Gi"
    error_message = "Airflow Postgres volume must be 50Gi"
  }
}

# The committed production sizing: one E5.Flex node, 1 OCPU, memory raised for the data
# platform. Node shape and size come from production.auto.tfvars, which tofu test loads.
run "test_production_node_sizing" {
  command = plan

  module {
    source = "./modules/oke"
  }

  variables {
    tenancy_ocid      = "ocid1.tenancy.oc1..test"
    prefix            = "sportsagentic"
    vcn_id            = "ocid1.vcn.oc1..test"
    k8s_api_subnet_id = "ocid1.subnet.oc1..api"
    lb_subnet_id      = "ocid1.subnet.oc1..lb"
    nodes_subnet_id   = "ocid1.subnet.oc1..nodes"
    cluster_type      = "BASIC_CLUSTER"
    k8s_version       = "v1.34.10"
  }

  assert {
    condition     = oci_containerengine_node_pool.model.node_shape == "VM.Standard.E5.Flex"
    error_message = "Production node must be VM.Standard.E5.Flex"
  }

  assert {
    condition     = oci_containerengine_node_pool.model.node_shape_config[0].ocpus == 1
    error_message = "Production node must stay at 1 OCPU"
  }

  assert {
    condition     = oci_containerengine_node_pool.model.node_shape_config[0].memory_in_gbs == 12
    error_message = "Production node memory must be 12 GB (see the memory budget in docs/data-platform.md)"
  }

  assert {
    condition     = oci_containerengine_node_pool.model.node_config_details[0].size == 1
    error_message = "Production node pool must have one node"
  }
}
