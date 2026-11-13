variable "compartment_id" {
  description = "Compartment OCID for the OCIR repositories."
  type        = string
}

variable "gcp_project_id" {
  description = "GCP project ID of the lakehouse. Set as GCP_PROJECT in Airflow containers."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.gcp_project_id))
    error_message = "gcp_project_id must be a valid GCP project ID (6-30 lowercase letters, digits or hyphens)."
  }
}

variable "storage_class_name" {
  description = "Storage class for the Kafka and Airflow Postgres volumes."
  type        = string
  default     = "oci-bv"
}

variable "image_pull_secret_name" {
  description = "Image pull secret for private OCIR images, referenced by the data service accounts. The Secret itself is not created here."
  type        = string
  default     = "ocir-pull"
}

variable "strimzi_chart_version" {
  description = "Version of the strimzi-kafka-operator Helm chart (also the operator image tag)."
  type        = string
  default     = "1.3.1"
}

variable "airflow_chart_version" {
  description = "Version of the official Apache Airflow Helm chart."
  type        = string
  default     = "1.22.0"
}

variable "airflow_credentials_secret_name" {
  description = "Name of the Secret in namespace data holding Airflow's fernet key, API and JWT secrets, metadata DB connection and Postgres password. Created by hand before the Airflow release (see docs/data-platform.md); never managed by OpenTofu."
  type        = string
  default     = "airflow-credentials"
}

variable "airflow_dags_repo_url" {
  description = "Git repository git-sync clones the Airflow DAGs from (public, no credentials)."
  type        = string
  default     = "https://github.com/tmonteith/SportsAgenticLakehouse.git"

  validation {
    condition     = startswith(var.airflow_dags_repo_url, "https://")
    error_message = "airflow_dags_repo_url must be an https:// URL (public repository, no credentials)."
  }
}

variable "airflow_dags_branch" {
  description = "Branch git-sync checks out."
  type        = string
  default     = "main"
}

variable "airflow_dags_sub_path" {
  description = "Directory inside the repository that holds the DAG files."
  type        = string
  default     = "dags"
}

variable "ingest_image_tag" {
  description = "Tag of the sportsagentic/extractor and sportsagentic/poller images (both built from the same commit). Empty (the default) installs nothing, so plans before the images exist change nothing."
  type        = string
  default     = ""

  validation {
    condition     = var.ingest_image_tag == "" || can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.ingest_image_tag))
    error_message = "ingest_image_tag must be empty or a valid image tag (letters, digits, '_', '.', '-'; at most 128 characters)."
  }
}

variable "drain_image_tag" {
  description = "Tag of the sportsagentic/spark-drain image. When set, every Airflow container gets AIRFLOW_VAR_SPARK_DRAIN_IMAGE (Airflow Variable spark_drain_image), the full image reference the stream_drain DAG runs. Empty (the default) leaves it unset."
  type        = string
  default     = ""

  validation {
    condition     = var.drain_image_tag == "" || can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.drain_image_tag))
    error_message = "drain_image_tag must be empty or a valid image tag (letters, digits, '_', '.', '-'; at most 128 characters)."
  }
}

variable "ocir_registry" {
  description = "OCIR registry host the lakehouse images are pulled from."
  type        = string
  default     = "ord.ocir.io"
}

variable "ocir_namespace" {
  description = "OCIR tenancy namespace of the lakehouse images (the tenancy's Object Storage namespace). Required when ingest_image_tag or drain_image_tag is set."
  type        = string
  default     = ""
}
