output "oke_nodes_dynamic_group_id" {
  description = "OCID of the OKE worker nodes dynamic group."
  value       = oci_identity_dynamic_group.oke_nodes.id
}

output "mcp_nodes_dynamic_group_name" {
  description = "Name of the MCP services pool dynamic group."
  value       = oci_identity_dynamic_group.mcp_nodes.name
}

output "mcp_nodes_dynamic_group_id" {
  description = "OCID of the MCP services pool dynamic group."
  value       = oci_identity_dynamic_group.mcp_nodes.id
}

output "app_ci_user_id" {
  description = "OCID of the App CI user."
  value       = oci_identity_user.app_ci_user.id
}

output "app_ci_group_id" {
  description = "OCID of the App CI group."
  value       = oci_identity_group.app_ci_group.id
}
