output "vcn_id" {
  description = "OCID of the VCN."
  value       = oci_core_vcn.main.id
}

output "k8s_api_subnet_id" {
  description = "OCID of the Kubernetes API endpoint subnet."
  value       = oci_core_subnet.k8s_api.id
}

output "lb_subnet_id" {
  description = "OCID of the public Load Balancer subnet."
  value       = oci_core_subnet.lb.id
}

output "nodes_subnet_id" {
  description = "OCID of the private worker nodes subnet."
  value       = oci_core_subnet.nodes.id
}

output "nat_gateway_id" {
  description = "OCID of the NAT Gateway."
  value       = oci_core_nat_gateway.nat.id
}

output "service_gateway_id" {
  description = "OCID of the Service Gateway."
  value       = oci_core_service_gateway.sgw.id
}
