output "ocir_registry_url" {
  description = "Docker registry base URL for pushing application container images."
  value       = "${var.region}.ocir.io/${data.oci_objectstorage_namespace.ns.namespace}/sportsagentic"
}

output "ocir_mcp_server_repository" {
  description = "Full OCIR repository image path for the MCP server."
  value       = "${var.region}.ocir.io/${data.oci_objectstorage_namespace.ns.namespace}/sportsagentic/mcp-server"
}

output "ocir_agent_model_repository" {
  description = "Full OCIR repository image path for the Agent model."
  value       = "${var.region}.ocir.io/${data.oci_objectstorage_namespace.ns.namespace}/sportsagentic/agent-model"
}

output "oke_cluster_id" {
  description = "OCID of the OKE Kubernetes cluster."
  value       = module.oke.cluster_id
}

output "oke_cluster_name" {
  description = "Name of the OKE Kubernetes cluster."
  value       = module.oke.cluster_name
}

output "available_kubernetes_versions" {
  description = "Available Kubernetes versions supported by OKE in this region."
  value       = module.oke.available_kubernetes_versions
}

output "oke_cluster_endpoint" {
  description = "Public API endpoint URL of the OKE cluster."
  value       = module.oke.cluster_endpoint
}

output "nosql_table_name" {
  description = "Name of the OCI NoSQL table."
  value       = module.platform.nosql_table_name
}

output "nosql_table_id" {
  description = "OCID of the OCI NoSQL table."
  value       = module.platform.nosql_table_id
}

output "app_namespace" {
  description = "Kubernetes namespace for SportsAgentic workloads."
  value       = module.platform.app_namespace
}

output "mcp_service_account" {
  description = "ServiceAccount name used by the MCP server pod."
  value       = module.platform.mcp_service_account_name
}

output "app_deployer_service_account" {
  description = "ServiceAccount name used by the CI/CD pipeline to deploy applications."
  value       = module.platform.app_deployer_service_account_name
}

output "dns_zone_name" {
  description = "Name of the authoritative OCI Public DNS Zone."
  value       = module.platform.dns_zone_name
}

output "dns_nameservers" {
  description = "Authoritative OCI nameservers to delegate at Porkbun."
  value       = module.platform.dns_nameservers
}
