variable "project_id" {
  description = "GCP project ID (<proj> in the lakehouse contracts). Bucket names are derived from it."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID."
  }
}

variable "region" {
  description = "GCP region for every resource. Always Free storage applies only in US regions, and the contracts fix it to us-central1."
  type        = string
  default     = "us-central1"

  validation {
    condition     = var.region == "us-central1"
    error_message = "The lakehouse contracts require region us-central1."
  }
}

variable "billing_account_display_name" {
  description = "Display name of the open Cloud Billing account the project is linked to (looked up, never hardcoded)."
  type        = string
}

variable "budget_alert_email" {
  description = "Email address that receives the $5, $10 and $20 budget alerts. Set it in terraform.tfvars (gitignored); never commit it."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_alert_email))
    error_message = "budget_alert_email must be an email address."
  }
}

variable "landing_retention_days" {
  description = "Days after which objects in the landing bucket are deleted."
  type        = number
  default     = 180

  validation {
    condition     = var.landing_retention_days >= 1 && floor(var.landing_retention_days) == var.landing_retention_days
    error_message = "landing_retention_days must be a positive integer."
  }
}
