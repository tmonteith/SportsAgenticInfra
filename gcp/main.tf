locals {
  # Contract names from the lakehouse plan ("Shared contracts"). Do not rename.
  buckets = {
    landing   = "${var.project_id}-sa-landing"
    warehouse = "${var.project_id}-sa-warehouse"
    gold      = "${var.project_id}-sa-gold"
    jobs      = "${var.project_id}-sa-jobs"
  }

  catalog_name = "sa_catalog"

  # Bronze and silver live in the warehouse bucket; gold lives in its own
  # bucket so the MCP identity can be given storage access to gold only.
  namespace_buckets = {
    bronze = "warehouse"
    silver = "warehouse"
    gold   = "gold"
  }

  # One GCP service account per workload ("sa-" prefix). sa-spark-runner never
  # gets a key: it only runs Serverless Spark batches inside GCP.
  service_accounts = {
    extractor      = "CFB extractor CronJob/Job on OKE: writes raw API responses to landing."
    "spark-drain"  = "Streaming drain pod on OKE: writes bronze and silver through the BigLake catalog."
    airflow        = "Airflow on OKE: submits Serverless Spark batches that run as sa-spark-runner."
    "mcp-server"   = "Go MCP server: reads gold tables through BigQuery."
    "spark-runner" = "Serverless Spark batches (no key; never leaves GCP)."
  }

  # Bucket-level grants, one row per line of the Security and auth table.
  # sa-extractor also views landing (amendment G1): it lists objects and reads
  # their metadata to skip responses it has already landed.
  bucket_iam = {
    "extractor-landing"        = { sa = "extractor", bucket = "landing", role = "roles/storage.objectCreator" }
    "extractor-landing-viewer" = { sa = "extractor", bucket = "landing", role = "roles/storage.objectViewer" }
    "spark-drain-warehouse"    = { sa = "spark-drain", bucket = "warehouse", role = "roles/storage.objectAdmin" }
    "airflow-landing"          = { sa = "airflow", bucket = "landing", role = "roles/storage.objectViewer" }
    "spark-runner-warehouse"   = { sa = "spark-runner", bucket = "warehouse", role = "roles/storage.objectAdmin" }
    "spark-runner-gold"        = { sa = "spark-runner", bucket = "gold", role = "roles/storage.objectAdmin" }
    "spark-runner-landing"     = { sa = "spark-runner", bucket = "landing", role = "roles/storage.objectViewer" }
    "spark-runner-jobs"        = { sa = "spark-runner", bucket = "jobs", role = "roles/storage.objectViewer" }
    "mcp-server-gold"          = { sa = "mcp-server", bucket = "gold", role = "roles/storage.objectViewer" }
  }

  # Namespace-level BigLake grants. Namespace IAM is inherited by the tables in
  # it, so sa-mcp-server can read gold tables and nothing in bronze or silver.
  namespace_iam = {
    "spark-drain-bronze" = { sa = "spark-drain", namespace = "bronze", role = "roles/biglake.editor" }
    "spark-drain-silver" = { sa = "spark-drain", namespace = "silver", role = "roles/biglake.editor" }
    "mcp-server-gold"    = { sa = "mcp-server", namespace = "gold", role = "roles/biglake.viewer" }
  }

  # Identities scoped to single namespaces probably also need to read the
  # catalog itself (Iceberg REST clients load the catalog config first, and the
  # docs do not say whether namespace grants cover that call). They get a custom
  # role holding only biglake.catalogs.get, which grants no namespace, table or
  # data access.
  catalog_getters = toset(["spark-drain", "mcp-server"])

  # Budget alerts at $5, $10 and $20 (contract). The budget amount is the
  # highest threshold; each alert is expressed as a fraction of it.
  budget_alerts_usd = [5, 10, 20]
  budget_amount_usd = max(local.budget_alerts_usd...)

  # Storage, BigLake, BigQuery, Dataproc, IAM and Billing Budgets per the plan,
  # plus Cloud Monitoring, which owns the email notification channel the
  # budget sends its alerts to.
  services = toset([
    "storage.googleapis.com",
    "biglake.googleapis.com",
    "bigquery.googleapis.com",
    "dataproc.googleapis.com",
    "iam.googleapis.com",
    "billingbudgets.googleapis.com",
    "monitoring.googleapis.com",
  ])
}

data "google_project" "this" {
  project_id = var.project_id
}

data "google_billing_account" "main" {
  display_name = var.billing_account_display_name
  open         = true
}

# 1. APIs
resource "google_project_service" "this" {
  for_each = local.services

  project                    = var.project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}

# 2. Buckets (single region, uniform access, public access prevention enforced)
resource "google_storage_bucket" "this" {
  for_each = local.buckets
  # checkov:skip=CKV_GCP_62:Access logs would need a second bucket and add cost; Cloud Audit Logs cover admin activity.
  # checkov:skip=CKV_GCP_78:Versioning is off by design: Iceberg keeps its own snapshots and landing objects are never overwritten.

  name                        = each.value
  location                    = upper(var.region)
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  dynamic "lifecycle_rule" {
    for_each = each.key == "landing" ? [var.landing_retention_days] : []
    content {
      condition {
        age = lifecycle_rule.value
      }
      action {
        type = "Delete"
      }
    }
  }

  depends_on = [google_project_service.this]
}

# 3. Service accounts (keys are minted outside OpenTofu by scripts/mint-keys.sh)
resource "google_service_account" "this" {
  for_each = local.service_accounts

  account_id   = "sa-${each.key}"
  display_name = "SportsAgentic sa-${each.key}"
  description  = each.value

  depends_on = [google_project_service.this]
}

# 4. Bucket-level IAM
resource "google_storage_bucket_iam_member" "this" {
  for_each = local.bucket_iam

  bucket = google_storage_bucket.this[each.value.bucket].name
  role   = each.value.role
  member = google_service_account.this[each.value.sa].member
}

# 5. Project-level IAM (only where GCP has no narrower resource)
# Dataproc batches have no resource-level IAM, so batch submission is granted
# on the project through a custom role holding only the batch permissions the
# Airflow Dataproc operators call, instead of roles/dataproc.editor.
resource "google_project_iam_custom_role" "dataproc_batch_submitter" {
  role_id     = "saDataprocBatchSubmitter"
  title       = "SportsAgentic Dataproc batch submitter"
  description = "Create, watch and cancel Serverless Spark batches. Used by sa-airflow."
  permissions = [
    "dataproc.batches.cancel",
    "dataproc.batches.create",
    "dataproc.batches.get",
    "dataproc.batches.list",
    "dataproc.operations.cancel",
    "dataproc.operations.get",
  ]

  depends_on = [google_project_service.this]
}

resource "google_project_iam_member" "airflow_dataproc_batches" {
  project = var.project_id
  role    = google_project_iam_custom_role.dataproc_batch_submitter.id
  member  = google_service_account.this["airflow"].member
}

resource "google_project_iam_member" "spark_runner_dataproc_worker" {
  project = var.project_id
  role    = "roles/dataproc.worker"
  member  = google_service_account.this["spark-runner"].member
}

resource "google_project_iam_member" "mcp_server_bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = google_service_account.this["mcp-server"].member
}

# sa-airflow may act as sa-spark-runner (granted on that service account only).
resource "google_service_account_iam_member" "airflow_acts_as_spark_runner" {
  service_account_id = google_service_account.this["spark-runner"].name
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.this["airflow"].member
}

# 6. BigLake (Lakehouse runtime catalog) Iceberg REST catalog
# A multiple-bucket catalog (CATALOG_TYPE_BIGLAKE) can be named independently
# of its buckets and span several of them: the default location is the
# warehouse bucket and the gold bucket is an extra allowed location. End-user
# credential mode means every caller needs its own storage access, which is
# what keeps sa-mcp-server out of the warehouse bucket.
resource "google_biglake_iceberg_catalog" "sa_catalog" {
  name             = local.catalog_name
  catalog_type     = "CATALOG_TYPE_BIGLAKE"
  credential_mode  = "CREDENTIAL_MODE_END_USER"
  default_location = "gs://${google_storage_bucket.this["warehouse"].name}"
  description      = "SportsAgentic lakehouse: bronze and silver in the warehouse bucket, gold in the gold bucket."

  restricted_locations_config {
    restricted_locations = [
      "gs://${google_storage_bucket.this["warehouse"].name}",
      "gs://${google_storage_bucket.this["gold"].name}",
    ]
  }

  depends_on = [google_project_service.this]
}

resource "google_biglake_iceberg_namespace" "this" {
  for_each = local.namespace_buckets

  catalog      = google_biglake_iceberg_catalog.sa_catalog.name
  namespace_id = each.key

  properties = {
    location = "gs://${google_storage_bucket.this[each.value].name}/${each.key}"
  }
}

resource "google_biglake_iceberg_catalog_iam_member" "spark_runner_editor" {
  project = var.project_id
  name    = google_biglake_iceberg_catalog.sa_catalog.name
  role    = "roles/biglake.editor"
  member  = google_service_account.this["spark-runner"].member
}

resource "google_project_iam_custom_role" "biglake_catalog_getter" {
  role_id     = "saBiglakeCatalogGetter"
  title       = "SportsAgentic BigLake catalog getter"
  description = "Read the sa_catalog definition only; grants no namespace, table or data access."
  permissions = ["biglake.catalogs.get"]

  depends_on = [google_project_service.this]
}

resource "google_biglake_iceberg_catalog_iam_member" "catalog_getter" {
  for_each = local.catalog_getters

  project = var.project_id
  name    = google_biglake_iceberg_catalog.sa_catalog.name
  role    = google_project_iam_custom_role.biglake_catalog_getter.id
  member  = google_service_account.this[each.key].member
}

resource "google_biglake_iceberg_namespace_iam_member" "this" {
  for_each = local.namespace_iam

  project      = var.project_id
  catalog      = google_biglake_iceberg_catalog.sa_catalog.name
  namespace_id = google_biglake_iceberg_namespace.this[each.value.namespace].namespace_id
  role         = each.value.role
  member       = google_service_account.this[each.value.sa].member
}

# 7. Billing budget with email alerts at $5, $10 and $20
resource "google_monitoring_notification_channel" "budget_email" {
  display_name = "SportsAgentic lakehouse budget alerts"
  type         = "email"

  labels = {
    email_address = var.budget_alert_email
  }

  depends_on = [google_project_service.this]
}

resource "google_billing_budget" "lakehouse" {
  billing_account = data.google_billing_account.main.id
  display_name    = "sportsagentic-lakehouse"

  budget_filter {
    projects        = ["projects/${data.google_project.this.number}"]
    calendar_period = "MONTH"
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(local.budget_amount_usd)
    }
  }

  dynamic "threshold_rules" {
    for_each = local.budget_alerts_usd
    content {
      threshold_percent = threshold_rules.value / local.budget_amount_usd
      spend_basis       = "CURRENT_SPEND"
    }
  }

  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.budget_email.id]
  }

  depends_on = [google_project_service.this]
}
