# Run from gcp/: tofu init -backend=false && tofu test
mock_provider "google" {
  mock_data "google_project" {
    defaults = {
      number = "123456789012"
    }
  }

  mock_data "google_billing_account" {
    defaults = {
      id = "000000-000000-000000"
    }
  }

  # IAM member resources validate the principal format, so mocked service
  # accounts need a well-formed member.
  mock_resource "google_service_account" {
    defaults = {
      member = "serviceAccount:mock-sa@sports-agent-511915.iam.gserviceaccount.com"
      name   = "projects/sports-agent-511915/serviceAccounts/mock-sa@sports-agent-511915.iam.gserviceaccount.com"
    }
  }
}

variables {
  project_id                   = "sports-agent-511915"
  billing_account_display_name = "Main"
  budget_alert_email           = "test-alert-recipient"
}

run "test_gcp_stack" {
  command = plan

  # Buckets: contract names, us-central1, locked down, landing expires after 180 days
  assert {
    condition = toset([for b in google_storage_bucket.this : b.name]) == toset([
      "sports-agent-511915-sa-landing",
      "sports-agent-511915-sa-warehouse",
      "sports-agent-511915-sa-gold",
      "sports-agent-511915-sa-jobs",
    ])
    error_message = "Bucket names must follow <proj>-sa-{landing,warehouse,gold,jobs}"
  }

  assert {
    condition = alltrue([for b in google_storage_bucket.this :
      b.location == "US-CENTRAL1" && b.uniform_bucket_level_access && b.public_access_prevention == "enforced" && b.force_destroy
    ])
    error_message = "Every bucket must be single-region us-central1, uniform access, public access prevention enforced, force_destroy"
  }

  assert {
    condition     = one([for c in google_storage_bucket.this["landing"].lifecycle_rule[0].condition : c.age]) == 180 && one([for a in google_storage_bucket.this["landing"].lifecycle_rule[0].action : a.type]) == "Delete"
    error_message = "Landing objects must be deleted after 180 days"
  }

  assert {
    condition     = length(google_storage_bucket.this["warehouse"].lifecycle_rule) == 0 && length(google_storage_bucket.this["gold"].lifecycle_rule) == 0
    error_message = "Only the landing bucket expires objects"
  }

  # Catalog and namespaces
  assert {
    condition     = google_biglake_iceberg_catalog.sa_catalog.name == "sa_catalog" && google_biglake_iceberg_catalog.sa_catalog.catalog_type == "CATALOG_TYPE_BIGLAKE"
    error_message = "Catalog must be the multiple-bucket catalog sa_catalog"
  }

  assert {
    condition     = google_biglake_iceberg_catalog.sa_catalog.default_location == "gs://sports-agent-511915-sa-warehouse"
    error_message = "Catalog warehouse must be the warehouse bucket"
  }

  assert {
    condition = (
      google_biglake_iceberg_namespace.this["bronze"].properties.location == "gs://sports-agent-511915-sa-warehouse/bronze" &&
      google_biglake_iceberg_namespace.this["silver"].properties.location == "gs://sports-agent-511915-sa-warehouse/silver" &&
      google_biglake_iceberg_namespace.this["gold"].properties.location == "gs://sports-agent-511915-sa-gold/gold"
    )
    error_message = "bronze and silver must live in the warehouse bucket and gold in the gold bucket"
  }

  # Service accounts: the five from the contract
  assert {
    condition     = toset([for sa in google_service_account.this : sa.account_id]) == toset(["sa-extractor", "sa-spark-drain", "sa-airflow", "sa-mcp-server", "sa-spark-runner"])
    error_message = "Service accounts must be sa-{extractor,spark-drain,airflow,mcp-server,spark-runner}"
  }

  # The extractor creates and views landing objects (amendment G1) and has no
  # access to any other bucket
  assert {
    condition = toset([for k, m in google_storage_bucket_iam_member.this : "${m.bucket}:${m.role}" if startswith(k, "extractor-")]) == toset([
      "sports-agent-511915-sa-landing:roles/storage.objectCreator",
      "sports-agent-511915-sa-landing:roles/storage.objectViewer",
    ])
    error_message = "sa-extractor must have exactly objectCreator and objectViewer on the landing bucket and nothing on the other buckets"
  }

  # The MCP identity reaches gold only
  assert {
    condition = toset([for k, m in google_storage_bucket_iam_member.this : "${m.bucket}:${m.role}" if startswith(k, "mcp-server-")]) == toset([
      "sports-agent-511915-sa-gold:roles/storage.objectViewer",
    ])
    error_message = "sa-mcp-server may only view objects in the gold bucket"
  }

  assert {
    condition = toset([for k, m in google_biglake_iceberg_namespace_iam_member.this : "${m.namespace_id}:${m.role}" if startswith(k, "mcp-server-")]) == toset([
      "gold:roles/biglake.viewer",
    ])
    error_message = "sa-mcp-server may only read the gold namespace"
  }

  assert {
    condition     = google_biglake_iceberg_catalog_iam_member.catalog_getter["mcp-server"].role != "roles/biglake.viewer" && google_project_iam_custom_role.biglake_catalog_getter.permissions == toset(["biglake.catalogs.get"])
    error_message = "The catalog-level grant for namespace-scoped identities must be biglake.catalogs.get only"
  }

  # Budget: $20 with alerts at $5, $10 and $20
  assert {
    condition     = google_billing_budget.lakehouse.amount[0].specified_amount[0].units == "20" && google_billing_budget.lakehouse.amount[0].specified_amount[0].currency_code == "USD"
    error_message = "Budget must be USD 20"
  }

  assert {
    condition     = [for r in google_billing_budget.lakehouse.threshold_rules : r.threshold_percent] == [0.25, 0.5, 1]
    error_message = "Budget alerts must fire at $5, $10 and $20"
  }

  assert {
    condition     = google_billing_budget.lakehouse.budget_filter[0].projects == toset(["projects/123456789012"])
    error_message = "Budget must be scoped to the project"
  }
}
