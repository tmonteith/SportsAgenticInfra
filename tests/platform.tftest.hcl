mock_provider "oci" {}
mock_provider "kubernetes" {}
mock_provider "helm" {}

run "test_platform_module" {
  command = plan

  module {
    source = "./modules/platform"
  }

  variables {
    tenancy_ocid                 = "ocid1.tenancy.oc1..test"
    compartment_id               = "ocid1.compartment.oc1..test"
    compartment_name             = "sportsagentic"
    identity_domain_name         = "Default"
    cluster_id                   = "ocid1.cluster.oc1..test"
    mcp_nodes_dynamic_group_name = "sportsagentic-mcp-nodes-dg"
    enable_oke_workload_identity = false
    prefix                       = "sportsagentic"
    lb_subnet_id                 = "ocid1.subnet.oc1..lb"
    domain_name                  = "sportagentic.dev"
    nosql_table_name             = "sportsagentic_cfb"
    nosql_max_read_units         = 50
    nosql_max_write_units        = 50
    nosql_max_storage_in_gbs     = 25
    letsencrypt_email            = "admin@sportagentic.dev"
  }

  # NoSQL assertions
  assert {
    condition     = oci_nosql_table.cfb.name == "sportsagentic_cfb"
    error_message = "NoSQL table name must match sportsagentic_cfb"
  }

  assert {
    condition     = oci_nosql_table.cfb.table_limits[0].max_read_units == 50
    error_message = "NoSQL max read units must be 50"
  }

  assert {
    condition     = oci_nosql_table.cfb.table_limits[0].max_write_units == 50
    error_message = "NoSQL max write units must be 50"
  }

  assert {
    condition     = oci_nosql_table.cfb.table_limits[0].max_storage_in_gbs == 25
    error_message = "NoSQL max storage in GBs must be 25"
  }

  # Scoped IAM NoSQL Policy assertions
  assert {
    condition     = contains(oci_identity_policy.nosql_mcp_access.statements, "Allow dynamic-group 'Default'/'sportsagentic-mcp-nodes-dg' to read nosql-tables in compartment sportsagentic")
    error_message = "NoSQL IAM policy must grant read nosql-tables to the MCP dynamic group"
  }

  assert {
    condition     = contains(oci_identity_policy.nosql_mcp_access.statements, "Allow dynamic-group 'Default'/'sportsagentic-mcp-nodes-dg' to read nosql-rows in compartment sportsagentic")
    error_message = "NoSQL IAM policy must grant read nosql-rows to the MCP dynamic group"
  }

  # DNS assertions
  assert {
    condition     = oci_dns_zone.main.name == "sportagentic.dev"
    error_message = "Public DNS zone name must be sportagentic.dev"
  }

  assert {
    condition     = oci_dns_zone.main.zone_type == "PRIMARY"
    error_message = "Public DNS zone type must be PRIMARY"
  }

  # OCIR Container Repositories assertions
  assert {
    condition     = oci_artifacts_container_repository.mcp_server.display_name == "sportsagentic/mcp-server"
    error_message = "MCP server repository display name must be sportsagentic/mcp-server"
  }

  assert {
    condition     = oci_artifacts_container_repository.agent_model.display_name == "sportsagentic/agent-model"
    error_message = "Agent model repository display name must be sportsagentic/agent-model"
  }

  # Kubernetes Platform assertions
  assert {
    condition     = kubernetes_namespace_v1.sportsagentic.metadata[0].name == "sportsagentic"
    error_message = "SportsAgentic namespace must be sportsagentic"
  }

  assert {
    condition     = kubernetes_service_account_v1.mcp_server.metadata[0].name == "mcp-server-sa"
    error_message = "MCP ServiceAccount name must be mcp-server-sa"
  }

  assert {
    condition     = helm_release.ingress_nginx.name == "ingress-nginx"
    error_message = "Ingress-nginx Helm release must be declared"
  }

  assert {
    condition     = helm_release.cert_manager.name == "cert-manager"
    error_message = "Cert-manager Helm release must be declared"
  }
}
