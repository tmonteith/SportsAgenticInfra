output "oke_nodes_dynamic_group_id" {
  description = "OCID of the OKE worker nodes dynamic group."
  value       = oci_identity_dynamic_group.oke_nodes.id
}

output "oke_nodes_dynamic_group_name" {
  description = "Name of the dynamic group matching every OKE worker node in the compartment."
  value       = oci_identity_dynamic_group.oke_nodes.name
}

output "mcp_nodes_dynamic_group_name" {
  description = "Name of the MCP services pool dynamic group."
  value       = oci_identity_dynamic_group.mcp_nodes.name
}

output "mcp_nodes_dynamic_group_id" {
  description = "OCID of the MCP services pool dynamic group."
  value       = oci_identity_dynamic_group.mcp_nodes.id
}
