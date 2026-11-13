mock_provider "oci" {
  mock_data "oci_identity_availability_domains" {
    defaults = {
      availability_domains = [
        {
          compartment_id = "ocid1.tenancy.oc1..test"
          id             = "ocid1.ad.oc1..test1"
          name           = "Uwhm:US-CHICAGO-1-AD-1"
        },
        {
          compartment_id = "ocid1.tenancy.oc1..test"
          id             = "ocid1.ad.oc1..test2"
          name           = "Uwhm:US-CHICAGO-1-AD-2"
        },
        {
          compartment_id = "ocid1.tenancy.oc1..test"
          id             = "ocid1.ad.oc1..test3"
          name           = "Uwhm:US-CHICAGO-1-AD-3"
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

  # tofu test loads production.auto.tfvars, which sets the live ingest tag. This run checks
  # the module with ingest off; test_ingest_release covers it on.
  variables {
    ingest_image_tag = ""
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

  # CRI-O on the nodes enforces short-name mode: a registry-less image name never pulls.
  assert {
    condition = alltrue([
      for r in [
        yamldecode(helm_release.airflow.values[0]).defaultAirflowRepository,
        yamldecode(helm_release.airflow.values[0]).images.airflow.repository,
        yamldecode(helm_release.airflow.values[0]).images.gitSync.repository,
      ] : can(regex("^[a-z0-9.-]+\\.[a-z]+/", r))
    ])
    error_message = "Airflow image repositories must include the registry host (e.g. docker.io/), because CRI-O rejects short names"
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

  # Ingest stays uninstalled until an image tag is set.
  assert {
    condition     = length(helm_release.ingest) == 0 && output.ingest_release == null && length(output.ingest_images) == 0
    error_message = "The ingest release must not be installed while ingest_image_tag is empty"
  }
}

run "test_ingest_release" {
  command = plan

  module {
    source = "./modules/data-platform"
  }

  variables {
    ingest_image_tag = "1234567"
    ocir_namespace   = "axtestnamespace"
  }

  assert {
    condition     = helm_release.ingest[0].name == "ingest" && helm_release.ingest[0].namespace == "data" && endswith(helm_release.ingest[0].chart, "k8s/data/ingest")
    error_message = "Ingest must be the local chart k8s/data/ingest, release ingest in namespace data"
  }

  # Image: ord.ocir.io/<tenancy-namespace>/sportsagentic/<name>:<tag>; a digits-only tag stays a string.
  assert {
    condition = (
      yamldecode(helm_release.ingest[0].values[1]).image.registry == "ord.ocir.io" &&
      yamldecode(helm_release.ingest[0].values[1]).image.namespace == "axtestnamespace" &&
      yamldecode(helm_release.ingest[0].values[1]).image.tag == "1234567" &&
      output.ingest_images.poller == "ord.ocir.io/axtestnamespace/sportsagentic/poller:1234567" &&
      output.ingest_images.extractor == "ord.ocir.io/axtestnamespace/sportsagentic/extractor:1234567"
    )
    error_message = "Ingest images must be ord.ocir.io/<namespace>/sportsagentic/{extractor,poller}:<ingest_image_tag>"
  }

  # Shared-contract env and secrets.
  assert {
    condition = (
      yamldecode(helm_release.ingest[0].values[1]).gcpProject == "sports-agent-test" &&
      yamldecode(helm_release.ingest[0].values[1]).kafkaBootstrap == "sa-kafka-kafka-bootstrap.data:9092" &&
      yamldecode(helm_release.ingest[0].values[0]).cfbdApiKeySecret.name == "cfbd-api-key" &&
      yamldecode(helm_release.ingest[0].values[0]).cfbdApiKeySecret.key == "CFBD_API_KEY" &&
      yamldecode(helm_release.ingest[0].values[0]).extractor.gcpKeySecret == "gcp-key-extractor" &&
      yamldecode(helm_release.ingest[0].values[1]).extractor.serviceAccountName == "extractor" &&
      yamldecode(helm_release.ingest[0].values[1]).imagePullSecrets == [{ name = "ocir-pull" }]
    )
    error_message = "Ingest must use GCP_PROJECT, KAFKA_BOOTSTRAP, Secrets cfbd-api-key and gcp-key-extractor, SA extractor and pull secret ocir-pull"
  }

  assert {
    condition = (
      yamldecode(helm_release.ingest[0].values[0]).extractor.schedule == "30 3 * * *" &&
      yamldecode(helm_release.ingest[0].values[0]).extractor.timeZone == "America/Denver" &&
      yamldecode(helm_release.ingest[0].values[0]).extractor.concurrencyPolicy == "Forbid"
    )
    error_message = "extractor-nightly must run at 03:30 America/Denver with concurrencyPolicy Forbid"
  }

  # Resource budget: poller <= 10m / 32Mi requests, 128Mi limit; extractor <= 50m / 128Mi, 256Mi.
  assert {
    condition = (
      output.ingest_resources.poller.cpu_request_m <= 10 &&
      output.ingest_resources.poller.memory_request_mib <= 32 &&
      output.ingest_resources.poller.memory_limit_mib <= 128 &&
      output.ingest_resources.extractor.cpu_request_m <= 50 &&
      output.ingest_resources.extractor.memory_request_mib <= 128 &&
      output.ingest_resources.extractor.memory_limit_mib <= 256 &&
      output.ingest_resources.poller.cpu_limit_m != null &&
      output.ingest_resources.extractor.cpu_limit_m != null
    )
    error_message = "Ingest containers must set requests and limits within the Phase 2 budget"
  }

  assert {
    condition = (
      yamldecode(helm_release.ingest[0].values[0]).podSecurityContext.runAsNonRoot &&
      yamldecode(helm_release.ingest[0].values[0]).containerSecurityContext.readOnlyRootFilesystem &&
      !yamldecode(helm_release.ingest[0].values[0]).containerSecurityContext.allowPrivilegeEscalation &&
      !yamldecode(helm_release.ingest[0].values[0]).backfill.enabled
    )
    error_message = "Ingest pods must run as non-root with a read-only root filesystem, and the backfill Job must not be part of the release"
  }
}

run "test_ingest_rejects_bad_tag" {
  command = plan

  module {
    source = "./modules/data-platform"
  }

  variables {
    ingest_image_tag = "latest; rm -rf"
    ocir_namespace   = "axtestnamespace"
  }

  expect_failures = [var.ingest_image_tag]
}

run "test_ingest_needs_ocir_namespace" {
  command = plan

  module {
    source = "./modules/data-platform"
  }

  variables {
    ingest_image_tag = "abc1234"
  }

  expect_failures = [helm_release.ingest]
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

  assert {
    condition = length(oci_containerengine_node_pool.model.node_config_details[0].placement_configs) == 1 && alltrue([
      for p in oci_containerengine_node_pool.model.node_config_details[0].placement_configs : endswith(p.availability_domain, "AD-3")
    ])
    error_message = "Production node pool must be pinned to AD-3, where its block volumes live"
  }
}

run "test_airflow_drain_image" {
  command = plan

  module {
    source = "./modules/data-platform"
  }

  variables {
    drain_image_tag = "a9a37da"
    ocir_namespace  = "axtestnamespace"
  }

  assert {
    condition = contains(
      [for e in yamldecode(helm_release.airflow.values[1]).env : e.value if e.name == "AIRFLOW_VAR_SPARK_DRAIN_IMAGE"],
      "ord.ocir.io/axtestnamespace/sportsagentic/spark-drain:a9a37da"
    )
    error_message = "Airflow must get AIRFLOW_VAR_SPARK_DRAIN_IMAGE with the full spark-drain image reference"
  }
}

run "test_airflow_no_drain_image_by_default" {
  command = plan

  module {
    source = "./modules/data-platform"
  }

  variables {
    ingest_image_tag = ""
    drain_image_tag  = ""
    ocir_namespace   = ""
  }

  assert {
    condition     = length([for e in yamldecode(helm_release.airflow.values[1]).env : e if e.name == "AIRFLOW_VAR_SPARK_DRAIN_IMAGE"]) == 0
    error_message = "Without drain_image_tag, Airflow must not get AIRFLOW_VAR_SPARK_DRAIN_IMAGE"
  }
}

run "test_drain_image_rejects_bad_tag" {
  command = plan

  module {
    source = "./modules/data-platform"
  }

  variables {
    ingest_image_tag = ""
    drain_image_tag  = "bad tag"
    ocir_namespace   = "axtestnamespace"
  }

  expect_failures = [var.drain_image_tag]
}
