mock_provider "oci" {
  mock_data "oci_core_services" {
    defaults = {
      services = [
        {
          cidr_block  = "all-iad-services-in-oracle-services-network"
          description = "All IAD Services In Oracle Services Network"
          id          = "ocid1.service.oc1.iad.aaaaaaaaxxxxxxxxx"
          name        = "All IAD Services In Oracle Services Network"
        }
      ]
    }
  }
}

run "test_network_module" {
  command = plan

  module {
    source = "./modules/network"
  }

  variables {
    compartment_id      = "ocid1.compartment.oc1..test"
    prefix              = "sportsagentic"
    vcn_cidr            = "10.0.0.0/16"
    k8s_api_subnet_cidr = "10.0.0.0/28"
    lb_subnet_cidr      = "10.0.1.0/24"
    nodes_subnet_cidr   = "10.0.10.0/24"
  }

  assert {
    condition     = oci_core_vcn.main.cidr_blocks[0] == "10.0.0.0/16"
    error_message = "VCN CIDR block must be 10.0.0.0/16"
  }

  assert {
    condition     = oci_core_vcn.main.dns_label == "sportsagentic"
    error_message = "VCN DNS label must be sportsagentic"
  }

  assert {
    condition     = oci_core_subnet.nodes.prohibit_public_ip_on_vnic == true
    error_message = "Worker nodes subnet must strictly prohibit public IPs"
  }

  assert {
    condition     = oci_core_subnet.k8s_api.prohibit_public_ip_on_vnic == false
    error_message = "K8s API endpoint subnet must allow public IPs"
  }

  assert {
    condition     = oci_core_subnet.lb.prohibit_public_ip_on_vnic == false
    error_message = "Load balancer subnet must allow public IPs"
  }

  assert {
    condition     = oci_core_internet_gateway.igw.enabled == true
    error_message = "Internet gateway must be enabled"
  }

  assert {
    condition     = length(oci_core_route_table.public.route_rules) == 1
    error_message = "Public route table must contain exactly one default route"
  }

  assert {
    condition     = length(oci_core_route_table.private.route_rules) == 2
    error_message = "Private route table must contain routes to NAT and Service Gateways"
  }
}

