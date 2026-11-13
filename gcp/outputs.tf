output "bucket_names" {
  description = "Lakehouse bucket names by role (landing, warehouse, gold, jobs)."
  value       = { for k, b in google_storage_bucket.this : k => b.name }
}

output "catalog_name" {
  description = "BigLake Iceberg REST catalog name (the second part of <proj>.sa_catalog.<namespace>.<table>)."
  value       = google_biglake_iceberg_catalog.sa_catalog.name
}

output "iceberg_namespaces" {
  description = "Iceberg namespaces and the Cloud Storage location each one stores its tables under."
  value       = { for k, n in google_biglake_iceberg_namespace.this : k => n.properties["location"] }
}

output "iceberg_rest_catalog_uri" {
  description = "Iceberg REST catalog endpoint for Spark clients (rest.auth.type = org.apache.iceberg.gcp.auth.GoogleAuthManager)."
  value       = "https://biglake.googleapis.com/iceberg/v1/restcatalog"
}

output "iceberg_warehouse" {
  description = "Warehouse value Spark clients pass for a multiple-bucket catalog."
  value       = "bl://projects/${var.project_id}/catalogs/${google_biglake_iceberg_catalog.sa_catalog.name}"
}

output "service_account_emails" {
  description = "GCP service account emails by workload (extractor, spark-drain, airflow, mcp-server, spark-runner)."
  value       = { for k, sa in google_service_account.this : k => sa.email }
}

output "billing_budget_name" {
  description = "Resource name of the lakehouse billing budget."
  value       = google_billing_budget.lakehouse.name
}

output "dataproc_subnet" {
  description = "Subnet name Serverless Spark batches pass as --subnet."
  value       = google_compute_subnetwork.dataproc.name
}
