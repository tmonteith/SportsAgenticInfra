terraform {
  # Created once by scripts/bootstrap-gcp-state.sh (single region, versioned,
  # uniform access, public access prevention enforced). Backend blocks cannot
  # read variables, so the bucket name is fixed here.
  backend "gcs" {
    bucket = "sports-agent-511915-sa-tfstate"
    prefix = "gcp"
  }
}
