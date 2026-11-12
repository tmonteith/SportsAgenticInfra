# Lakehouse ingestion: the CFBD extractor (nightly CronJob extractor-nightly) and the
# game-day poller (Deployment poller), as the local chart k8s/data/ingest. Installed only
# once their images exist, i.e. when var.ingest_image_tag is set; until then plans change
# nothing. Backfills render a one-off Job from the same chart (scripts/backfill.sh).

locals {
  ingest_values  = yamldecode(file("${local.k8s_dir}/ingest/values.yaml"))
  ingest_enabled = var.ingest_image_tag != ""

  ingest_images = {
    for name in ["extractor", "poller"] :
    name => "${var.ocir_registry}/${var.ocir_namespace}/sportsagentic/${name}:${var.ingest_image_tag}"
  }

  # Requests and limits of every container in the chart, in millicores and MiB, for the
  # budget checks below (null when a value is missing).
  ingest_container_resources = {
    extractor = local.ingest_values.extractor.resources
    poller    = local.ingest_values.poller.resources
  }
  ingest_resources = {
    for name, r in local.ingest_container_resources : name => {
      cpu_request_m = try(
        endswith(tostring(r.requests.cpu), "m") ? tonumber(trimsuffix(tostring(r.requests.cpu), "m")) : tonumber(r.requests.cpu) * 1000,
        null,
      )
      cpu_limit_m = try(
        endswith(tostring(r.limits.cpu), "m") ? tonumber(trimsuffix(tostring(r.limits.cpu), "m")) : tonumber(r.limits.cpu) * 1000,
        null,
      )
      memory_request_mib = try(
        tonumber(regex("^([0-9]+)(Mi|Gi)$", r.requests.memory)[0]) * (regex("^([0-9]+)(Mi|Gi)$", r.requests.memory)[1] == "Gi" ? 1024 : 1),
        null,
      )
      memory_limit_mib = try(
        tonumber(regex("^([0-9]+)(Mi|Gi)$", r.limits.memory)[0]) * (regex("^([0-9]+)(Mi|Gi)$", r.limits.memory)[1] == "Gi" ? 1024 : 1),
        null,
      )
    }
  }

  # Resource budget (requests / limits) decided for Phase 2.
  ingest_budget = {
    extractor = { cpu_request_m = 50, memory_request_mib = 128, memory_limit_mib = 256 }
    poller    = { cpu_request_m = 10, memory_request_mib = 32, memory_limit_mib = 128 }
  }
}

resource "helm_release" "ingest" {
  count = local.ingest_enabled ? 1 : 0

  name      = "ingest"
  chart     = "${local.k8s_dir}/ingest"
  namespace = kubernetes_namespace_v1.data.metadata[0].name

  values = [
    file("${local.k8s_dir}/ingest/values.yaml"),
    yamlencode({
      image = {
        registry  = var.ocir_registry
        namespace = var.ocir_namespace
        tag       = var.ingest_image_tag
      }
      imagePullSecrets = [{ name = var.image_pull_secret_name }]
      gcpProject       = var.gcp_project_id
      kafkaBootstrap   = local.kafka_bootstrap
      extractor = {
        serviceAccountName = kubernetes_service_account_v1.workload["extractor"].metadata[0].name
      }
    }),
  ]

  # The poller produces to cfb.live_games, a KafkaTopic of the Kafka release. The Secrets
  # cfbd-api-key, ocir-pull and gcp-key-extractor come from modules/secrets, which
  # depends on this module, so they must exist before ingest_image_tag is set
  # (docs/data-platform.md, section 8).
  depends_on = [helm_release.kafka]

  lifecycle {
    precondition {
      condition     = var.ocir_namespace != ""
      error_message = "ocir_namespace (the OCIR tenancy namespace) must be set to install the ingest release."
    }
    precondition {
      condition = alltrue(flatten([
        for name, r in local.ingest_resources : [for v in values(r) : v != null]
      ]))
      error_message = "Every ingest container must set CPU and memory requests and limits (k8s/data/ingest/values.yaml)."
    }
    precondition {
      condition = alltrue([
        for name, b in local.ingest_budget :
        local.ingest_resources[name].cpu_request_m <= b.cpu_request_m &&
        local.ingest_resources[name].memory_request_mib <= b.memory_request_mib &&
        local.ingest_resources[name].memory_limit_mib <= b.memory_limit_mib
      ])
      error_message = "Ingest resources exceed the budget: poller <= 10m CPU request and 32Mi/128Mi memory, extractor <= 50m CPU request and 128Mi/256Mi memory."
    }
    precondition {
      condition = alltrue([
        for name, r in local.ingest_resources :
        r.cpu_request_m <= r.cpu_limit_m && r.memory_request_mib <= r.memory_limit_mib
      ])
      error_message = "Ingest resource requests must not exceed their limits."
    }
    precondition {
      condition = (
        local.ingest_values.extractor.schedule == "30 3 * * *" &&
        local.ingest_values.extractor.timeZone == "America/Denver" &&
        local.ingest_values.extractor.concurrencyPolicy == "Forbid"
      )
      error_message = "extractor-nightly must run at 03:30 America/Denver with concurrencyPolicy Forbid."
    }
    precondition {
      condition = (
        local.ingest_values.podSecurityContext.runAsNonRoot &&
        local.ingest_values.containerSecurityContext.readOnlyRootFilesystem &&
        !local.ingest_values.containerSecurityContext.allowPrivilegeEscalation
      )
      error_message = "Ingest pods must run as non-root with a read-only root filesystem and no privilege escalation."
    }
  }
}
