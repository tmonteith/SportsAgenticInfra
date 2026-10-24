output "ocir_mcp_server_repository_id" {
  description = "OCID of the MCP server container repository."
  value       = oci_artifacts_container_repository.mcp_server.id
}

output "ocir_agent_model_repository_id" {
  description = "OCID of the Agent model container repository."
  value       = oci_artifacts_container_repository.agent_model.id
}

output "nosql_table_name" {
  description = "Name of the OCI NoSQL table."
  value       = oci_nosql_table.cfb.name
}

output "nosql_table_id" {
  description = "OCID of the OCI NoSQL table."
  value       = oci_nosql_table.cfb.id
}

output "dns_zone_name" {
  description = "Name of the public DNS zone."
  value       = oci_dns_zone.main.name
}

output "dns_nameservers" {
  description = "Authoritative OCI nameservers for domain delegation at Porkbun."
  value       = oci_dns_zone.main.nameservers
}

output "app_namespace" {
  description = "Target Kubernetes namespace for application deployments."
  value       = kubernetes_namespace_v1.sportsagentic.metadata[0].name
}

output "mcp_service_account_name" {
  description = "Name of the MCP server Kubernetes ServiceAccount."
  value       = kubernetes_service_account_v1.mcp_server.metadata[0].name
}

output "app_deployer_service_account_name" {
  description = "Name of the App pipeline deployer Kubernetes ServiceAccount."
  value       = kubernetes_service_account_v1.app_deployer.metadata[0].name
}
