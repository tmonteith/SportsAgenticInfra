provider "google" {
  project = var.project_id
  region  = var.region

  # Bill API quota to this project. Needed when applying with user credentials
  # (gcloud auth application-default login): the BigLake Iceberg IAM resources
  # and the billing budget both return 403 without a quota project.
  billing_project       = var.project_id
  user_project_override = true

  # GCP label keys and values must be lowercase, so these mirror the OCI
  # freeform tags Project = "SportsAgentic" and ManagedBy = "OpenTofu".
  default_labels = {
    project    = "sportsagentic"
    managed-by = "opentofu"
  }
}
