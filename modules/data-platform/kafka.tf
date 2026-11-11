# Strimzi operator, then the Kafka cluster and topics as a small local chart (the CRs need
# the operator's CRDs, same pattern as modules/platform/charts/cluster-issuer).

locals {
  kafka_values = yamldecode(file("${local.k8s_dir}/kafka/values.yaml"))

  kafka_heap_mib = (
    tonumber(regex("^([0-9]+)([mMgG])$", local.kafka_values.nodePool.heap)[0]) *
    (lower(regex("^([0-9]+)([mMgG])$", local.kafka_values.nodePool.heap)[1]) == "g" ? 1024 : 1)
  )
  kafka_memory_limit_mib = (
    tonumber(regex("^([0-9]+)(Mi|Gi)$", local.kafka_values.nodePool.resources.limits.memory)[0]) *
    (regex("^([0-9]+)(Mi|Gi)$", local.kafka_values.nodePool.resources.limits.memory)[1] == "Gi" ? 1024 : 1)
  )
  kafka_topic_names = [for t in local.kafka_values.topics : t.topicName]
}

resource "helm_release" "strimzi" {
  name       = "strimzi-kafka-operator"
  repository = "https://strimzi.io/charts/"
  chart      = "strimzi-kafka-operator"
  version    = var.strimzi_chart_version
  namespace  = kubernetes_namespace_v1.data.metadata[0].name

  values = [file("${local.k8s_dir}/strimzi/values.yaml")]
}

resource "helm_release" "kafka" {
  name      = local.kafka_cluster_name
  chart     = "${local.k8s_dir}/kafka"
  namespace = kubernetes_namespace_v1.data.metadata[0].name

  values = [
    file("${local.k8s_dir}/kafka/values.yaml"),
    yamlencode({
      storage = {
        class = var.storage_class_name
      }
    }),
  ]

  depends_on = [helm_release.strimzi]

  lifecycle {
    precondition {
      condition     = local.kafka_values.clusterName == local.kafka_cluster_name
      error_message = "k8s/data/kafka/values.yaml clusterName must be sa-kafka (shared contract)."
    }
    precondition {
      condition     = local.kafka_heap_mib <= 768
      error_message = "Kafka JVM heap must be at most 768 MiB."
    }
    precondition {
      condition     = local.kafka_memory_limit_mib <= 1280
      error_message = "Kafka memory limit must be at most 1280Mi (1.25 GiB)."
    }
    precondition {
      condition     = local.kafka_values.storage.size == "50Gi"
      error_message = "The Kafka volume must be 50Gi (OCI minimum; Always Free block storage budget)."
    }
    precondition {
      condition     = alltrue([for l in local.kafka_values.kafka.listeners : l.type == "internal"])
      error_message = "Kafka listeners must be cluster-internal only."
    }
    precondition {
      condition     = toset(local.kafka_topic_names) == toset(["cfb.live_games", "agent.events"])
      error_message = "Kafka topics must be exactly cfb.live_games and agent.events (shared contract)."
    }
  }
}
