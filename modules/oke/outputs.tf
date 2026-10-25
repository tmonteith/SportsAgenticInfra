output "cluster_id" {
  description = "OCID of the OKE cluster."
  value       = oci_containerengine_cluster.main.id
}

output "cluster_name" {
  description = "Name of the OKE cluster."
  value       = oci_containerengine_cluster.main.name
}

output "cluster_endpoint" {
  description = "Public endpoint URL of the OKE cluster control plane."
  value       = try(oci_containerengine_cluster.main.endpoints[0].public_endpoint, "")
}

output "kubeconfig" {
  description = "Kubernetes kubeconfig file content."
  value       = data.oci_containerengine_cluster_kube_config.kubeconfig.content
  sensitive   = true
}

output "model_node_pool_id" {
  description = "OCID of the model node pool."
  value       = oci_containerengine_node_pool.model.id
}

output "node_image_id" {
  description = "Discovered worker node image OCID."
  value       = local.node_image_id
}

output "available_kubernetes_versions" {
  description = "Available Kubernetes versions for OKE in this region."
  value       = data.oci_containerengine_node_pool_option.oke_all.kubernetes_versions
}
