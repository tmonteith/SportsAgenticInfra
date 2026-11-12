output "namespace" {
  description = "Kubernetes namespace of the data platform (Kafka, Airflow, lakehouse jobs)."
  value       = kubernetes_namespace_v1.data.metadata[0].name
}

output "kafka_cluster_name" {
  description = "Name of the Strimzi Kafka cluster."
  value       = local.kafka_cluster_name
}

output "kafka_bootstrap" {
  description = "In-cluster Kafka bootstrap address (KAFKA_BOOTSTRAP)."
  value       = local.kafka_bootstrap
}

output "kafka_topics" {
  description = "Kafka topic names managed by the topic operator."
  value       = local.kafka_topic_names
}

output "service_account_names" {
  description = "Workload service accounts in the data namespace."
  value       = { for k, sa in kubernetes_service_account_v1.workload : k => sa.metadata[0].name }
}

output "ocir_repository_ids" {
  description = "OCIDs of the lakehouse OCIR repositories, keyed by image name."
  value       = { for k, r in oci_artifacts_container_repository.data : k => r.id }
}

output "airflow_api_service" {
  description = "ClusterIP service of the Airflow API server (UI via kubectl port-forward)."
  value       = "${helm_release.airflow.name}-api-server"
}

output "memory_limits_mib" {
  description = "Memory limits (MiB) this module sets: Kafka broker and heap, and each Airflow container plus their total."
  value = {
    kafka_broker  = local.kafka_memory_limit_mib
    kafka_heap    = local.kafka_heap_mib
    airflow       = local.airflow_memory_limits_mib
    airflow_total = local.airflow_memory_limit_total_mib
  }
}

output "ingest_release" {
  description = "Name of the ingest Helm release (extractor CronJob and poller), or null while ingest_image_tag is empty."
  value       = local.ingest_enabled ? helm_release.ingest[0].name : null
}

output "ingest_images" {
  description = "Extractor and poller image references, or an empty map while ingest_image_tag is empty."
  value       = local.ingest_enabled ? local.ingest_images : {}
}

output "ingest_resources" {
  description = "CPU (millicores) and memory (MiB) requests and limits of the extractor and poller containers."
  value       = local.ingest_resources
}
