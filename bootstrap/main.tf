terraform {
  required_version = ">= 1.8.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
  }
}

provider "oci" {
  tenancy_ocid        = var.tenancy_ocid
  user_ocid           = var.user_ocid
  fingerprint         = var.fingerprint
  private_key         = var.private_key
  private_key_path    = var.private_key_path != null ? pathexpand(var.private_key_path) : null
  config_file_profile = var.config_file_profile
  region              = var.region
}

# Fetch Object Storage Namespace for Tenancy
data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.tenancy_ocid
}

# 1. Dedicated Compartment for SportsAgentic
resource "oci_identity_compartment" "sportsagentic" {
  compartment_id = var.tenancy_ocid
  name           = var.compartment_name
  description    = var.compartment_description
  enable_delete  = false
}

# 2. Remote State Object Storage Bucket (Versioned & Private)
resource "oci_objectstorage_bucket" "tfstate" {
  compartment_id        = oci_identity_compartment.sportsagentic.id
  name                  = var.tfstate_bucket_name
  namespace             = data.oci_objectstorage_namespace.ns.namespace
  access_type           = "NoPublicAccess"
  versioning            = "Enabled"
  auto_tiering          = "Disabled"
  storage_tier          = "Standard"
  object_events_enabled = true

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu-Bootstrap"
    "Purpose"   = "RemoteState"
  }
}

# 3. CI/CD Service Account Group
resource "oci_identity_group" "ci_group" {
  compartment_id = var.tenancy_ocid
  name           = "${var.compartment_name}-ci-group"
  description    = "Dedicated IAM group for SportsAgentic CI/CD pipelines"

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu-Bootstrap"
  }
}

# 4. CI/CD Service Account User
resource "oci_identity_user" "ci_user" {
  compartment_id = var.tenancy_ocid
  name           = "${var.compartment_name}-ci"
  description    = "Service account user for GitHub Actions OpenTofu automation"

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu-Bootstrap"
  }
}

# 5. User-Group Membership
resource "oci_identity_user_group_membership" "ci_membership" {
  group_id = oci_identity_group.ci_group.id
  user_id  = oci_identity_user.ci_user.id
}

# 6. Generate RSA 2048-bit Key Pair for OCI API Authentication
resource "tls_private_key" "ci_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# 7. Upload Public Key as OCI API Key for CI User
resource "oci_identity_api_key" "ci_api_key" {
  user_id   = oci_identity_user.ci_user.id
  key_value = tls_private_key.ci_key.public_key_pem
}

# 8. Customer Secret Key for S3-Compatible Remote State Backend Access
resource "oci_identity_customer_secret_key" "ci_s3_key" {
  user_id      = oci_identity_user.ci_user.id
  display_name = "${var.compartment_name}-ci-s3-state-key"
}

# Local helper to handle Identity Domain vs Classic IAM group naming
locals {
  group_ref = (var.identity_domain_name != "" && lower(var.identity_domain_name) != "default") ? "'${var.identity_domain_name}'/'${oci_identity_group.ci_group.name}'" : oci_identity_group.ci_group.name
}

# 9. Scoped IAM Policy for CI Pipeline
resource "oci_identity_policy" "ci_policy" {
  compartment_id = var.tenancy_ocid
  name           = "${var.compartment_name}-ci-policy"
  description    = "Grants the SportsAgentic CI service account scoped permissions to manage the workload compartment and state bucket"

  statements = [
    # Full resource management within the designated workload compartment
    "Allow group ${local.group_ref} to manage all-resources in compartment ${oci_identity_compartment.sportsagentic.name}",

    # Read/inspect tenancy metadata needed by the OCI provider
    "Allow group ${local.group_ref} to read compartments in tenancy",
    "Allow group ${local.group_ref} to inspect tenancies in tenancy",

    # Dynamic group management (needed for OKE worker nodes & cluster registration)
    "Allow group ${local.group_ref} to manage dynamic-groups in tenancy"
  ]

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu-Bootstrap"
  }
}
