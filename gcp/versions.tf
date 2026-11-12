terraform {
  # CI pins OpenTofu 1.8.8, so nothing newer than 1.8 syntax is used here.
  required_version = ">= 1.8.0"
  required_providers {
    google = {
      source = "hashicorp/google"
      # google_biglake_iceberg_catalog with CATALOG_TYPE_BIGLAKE,
      # restricted_locations_config and namespace locations need >= 7.38.0.
      version = "~> 8.10.0"
    }
  }
}
