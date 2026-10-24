output "tenancy_ocid" {
  description = "The Tenancy OCID."
  value       = var.tenancy_ocid
}

output "compartment_ocid" {
  description = "OCID of the newly created sportsagentic compartment."
  value       = oci_identity_compartment.sportsagentic.id
}

output "compartment_name" {
  description = "Name of the sportsagentic compartment."
  value       = oci_identity_compartment.sportsagentic.name
}

output "region" {
  description = "OCI region."
  value       = var.region
}

output "object_storage_namespace" {
  description = "Object Storage namespace for the tenancy."
  value       = data.oci_objectstorage_namespace.ns.namespace
}

output "tfstate_bucket_name" {
  description = "Name of the remote state Object Storage bucket."
  value       = oci_objectstorage_bucket.tfstate.name
}

output "tfstate_s3_endpoint" {
  description = "S3-compatible endpoint URL for the OpenTofu state bucket."
  value       = "https://${data.oci_objectstorage_namespace.ns.namespace}.compat.objectstorage.${var.region}.oraclecloud.com"
}

output "ci_user_ocid" {
  description = "OCID of the CI/CD service user."
  value       = oci_identity_user.ci_user.id
}

output "ci_user_fingerprint" {
  description = "Fingerprint of the CI user API key."
  value       = oci_identity_api_key.ci_api_key.fingerprint
}

output "ci_private_key_pem" {
  description = "Private RSA key for the CI user."
  value       = tls_private_key.ci_key.private_key_pem
  sensitive   = true
}

output "s3_access_key_id" {
  description = "Access key ID for S3-compatible backend."
  value       = oci_identity_customer_secret_key.ci_s3_key.id
}

output "s3_secret_access_key" {
  description = "Secret access key for S3-compatible backend."
  value       = oci_identity_customer_secret_key.ci_s3_key.key
  sensitive   = true
}

output "github_secrets_export_script" {
  description = "Bash command script to configure repository secrets via GitHub CLI."
  sensitive   = true
  value       = <<-EOT
    gh secret set OCI_TENANCY_OCID --body "${var.tenancy_ocid}"
    gh secret set OCI_USER_OCID --body "${oci_identity_user.ci_user.id}"
    gh secret set OCI_FINGERPRINT --body "${oci_identity_api_key.ci_api_key.fingerprint}"
    gh secret set OCI_REGION --body "${var.region}"
    gh secret set OCI_COMPARTMENT_OCID --body "${oci_identity_compartment.sportsagentic.id}"
    gh secret set OCI_PRIVATE_KEY --body "${tls_private_key.ci_key.private_key_pem}"
    gh secret set AWS_ACCESS_KEY_ID --body "${oci_identity_customer_secret_key.ci_s3_key.id}"
    gh secret set AWS_SECRET_ACCESS_KEY --body "${oci_identity_customer_secret_key.ci_s3_key.key}"
    gh secret set TFSTATE_BUCKET --body "${oci_objectstorage_bucket.tfstate.name}"
    gh secret set TFSTATE_S3_ENDPOINT --body "https://${data.oci_objectstorage_namespace.ns.namespace}.compat.objectstorage.${var.region}.oraclecloud.com"
  EOT
}
