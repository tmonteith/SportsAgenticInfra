# Apache Airflow (official chart): LocalExecutor, bundled Postgres, port-forward only.
# Static settings and sizing are in k8s/data/airflow/values.yaml; this file adds the
# environment-specific values.

locals {
  airflow_values = yamldecode(file("${local.k8s_dir}/airflow/values.yaml"))

  # Memory limit of every Airflow container that can run, including sidecars, Postgres
  # and the migration job. With LocalExecutor, git-sync runs in both the scheduler and
  # the dag-processor pod.
  airflow_memory_limits = {
    "scheduler"                 = local.airflow_values.scheduler.resources.limits.memory
    "scheduler/git-sync"        = local.airflow_values.dags.gitSync.resources.limits.memory
    "scheduler/log-groomer"     = local.airflow_values.scheduler.logGroomerSidecar.resources.limits.memory
    "api-server"                = local.airflow_values.apiServer.resources.limits.memory
    "dag-processor"             = local.airflow_values.dagProcessor.resources.limits.memory
    "dag-processor/git-sync"    = local.airflow_values.dags.gitSync.resources.limits.memory
    "dag-processor/log-groomer" = local.airflow_values.dagProcessor.logGroomerSidecar.resources.limits.memory
    "postgresql"                = local.airflow_values.postgresql.primary.resources.limits.memory
    "run-airflow-migrations"    = local.airflow_values.migrateDatabaseJob.resources.limits.memory
  }

  airflow_memory_limits_mib = {
    for name, q in local.airflow_memory_limits :
    name => tonumber(regex("^([0-9]+)(Mi|Gi)$", q)[0]) * (regex("^([0-9]+)(Mi|Gi)$", q)[1] == "Gi" ? 1024 : 1)
  }
  airflow_memory_limit_total_mib = sum(values(local.airflow_memory_limits_mib))

  airflow_service_account = kubernetes_service_account_v1.workload["airflow"].metadata[0].name
  airflow_sa_values = {
    serviceAccount = {
      create = false
      name   = local.airflow_service_account
    }
  }

  airflow_dynamic_values = {
    # All Airflow secrets come from one Secret the user creates (docs/data-platform.md).
    # The chart generates none, so nothing changes on upgrade and nothing is in state.
    fernetKeySecretName    = var.airflow_credentials_secret_name
    apiSecretKeySecretName = var.airflow_credentials_secret_name
    jwtSecretName          = var.airflow_credentials_secret_name
    data = {
      metadataSecretName = var.airflow_credentials_secret_name
      # Celery only and never read with LocalExecutor; set so the chart does not create
      # an empty broker-URL Secret as an install hook.
      brokerUrlSecretName = var.airflow_credentials_secret_name
    }
    postgresql = {
      auth = {
        existingSecret = var.airflow_credentials_secret_name
        secretKeys = {
          adminPasswordKey = "postgres-password"
        }
      }
      primary = {
        persistence = {
          storageClass = var.storage_class_name
        }
      }
    }

    # Every Airflow component runs as the service account "airflow".
    scheduler          = local.airflow_sa_values
    apiServer          = local.airflow_sa_values
    dagProcessor       = local.airflow_sa_values
    migrateDatabaseJob = local.airflow_sa_values
    createUserJob      = local.airflow_sa_values
    triggerer          = local.airflow_sa_values

    # Shared contract env vars for every Airflow container (and so every task).
    env = [
      { name = "GOOGLE_APPLICATION_CREDENTIALS", value = local.gcp_key_file },
      { name = "GCP_PROJECT", value = var.gcp_project_id },
      { name = "ICEBERG_CATALOG", value = local.iceberg_catalog },
      { name = "KAFKA_BOOTSTRAP", value = local.kafka_bootstrap },
    ]

    # Key Secret synced by External Secrets (WS1). Optional, so pods start before it exists.
    volumes = [
      {
        name = "gcp-key"
        secret = {
          secretName = "gcp-key-airflow"
          optional   = true
        }
      },
    ]
    volumeMounts = [
      {
        name      = "gcp-key"
        mountPath = local.gcp_key_mount_path
        readOnly  = true
      },
    ]

    dags = {
      gitSync = {
        repo    = var.airflow_dags_repo_url
        branch  = var.airflow_dags_branch
        ref     = var.airflow_dags_branch
        subPath = var.airflow_dags_sub_path
      }
    }
  }
}

resource "helm_release" "airflow" {
  name       = "airflow"
  repository = "https://airflow.apache.org"
  chart      = "airflow"
  version    = var.airflow_chart_version
  namespace  = kubernetes_namespace_v1.data.metadata[0].name

  # First install pulls the ~1 GB Airflow image and runs the DB migration.
  timeout = 900

  values = [
    file("${local.k8s_dir}/airflow/values.yaml"),
    yamlencode(local.airflow_dynamic_values),
  ]

  depends_on = [kubernetes_role_binding_v1.airflow_pod_launcher]

  lifecycle {
    precondition {
      condition     = local.airflow_memory_limit_total_mib <= 3072
      error_message = "The sum of Airflow memory limits (Postgres, sidecars and the migration job included) must be at most 3 GiB."
    }
    precondition {
      condition     = local.airflow_values.executor == "LocalExecutor"
      error_message = "Airflow must use LocalExecutor."
    }
    precondition {
      condition     = !local.airflow_values.triggerer.enabled
      error_message = "The Airflow triggerer must stay disabled."
    }
    precondition {
      condition     = local.airflow_values.apiServer.service.type == "ClusterIP" && !local.airflow_values.ingress.apiServer.enabled && !local.airflow_values.ingress.web.enabled
      error_message = "The Airflow API server must not be exposed (ClusterIP, no Ingress; port-forward only)."
    }
    precondition {
      condition     = local.airflow_values.postgresql.primary.persistence.size == "50Gi"
      error_message = "The Airflow Postgres volume must be 50Gi."
    }
  }
}
