# Query available OCI Services for Service Gateway
data "oci_core_services" "all_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

# 1. Virtual Cloud Network (VCN)
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.prefix}-vcn"
  dns_label      = var.prefix
  is_ipv6enabled = false

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# 2. Gateways
resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-igw"
  enabled        = true

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

resource "oci_core_nat_gateway" "nat" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-nat-gw"

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

resource "oci_core_service_gateway" "sgw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-service-gw"

  services {
    service_id = data.oci_core_services.all_services.services[0].id
  }

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# 3. Route Tables
resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-private-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.nat.id
  }

  route_rules {
    destination       = data.oci_core_services.all_services.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.sgw.id
  }

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# 4. Security Lists
# A. Kubernetes API Endpoint Security List
resource "oci_core_security_list" "k8s_api" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-k8s-api-sl"

  # Ingress: Allow Kubernetes API access from authorized CIDRs (6443)
  dynamic "ingress_security_rules" {
    for_each = var.k8s_api_allowed_cidrs
    content {
      protocol    = "6" # TCP
      source      = ingress_security_rules.value
      source_type = "CIDR_BLOCK"
      stateless   = false
      description = "Kubernetes API endpoint"

      tcp_options {
        min = 6443
        max = 6443
      }
    }
  }

  # Ingress: Worker nodes to API server (12250)
  ingress_security_rules {
    protocol    = "6"
    source      = var.nodes_subnet_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false
    description = "Worker nodes to Kubernetes control plane"

    tcp_options {
      min = 12250
      max = 12250
    }
  }

  # Ingress: ICMP Path MTU Discovery
  ingress_security_rules {
    protocol    = "1"
    source      = var.nodes_subnet_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false
    description = "ICMP Path MTU discovery"

    icmp_options {
      type = 3
      code = 4
    }
  }

  # Egress: Control plane to worker node kubelet (10250)
  egress_security_rules {
    protocol         = "6"
    destination      = var.nodes_subnet_cidr
    destination_type = "CIDR_BLOCK"
    stateless        = false
    description      = "Control plane to kubelet"

    tcp_options {
      min = 10250
      max = 10250
    }
  }

  # Egress: Control plane to Services Network (OSN)
  egress_security_rules {
    protocol         = "6"
    destination      = data.oci_core_services.all_services.services[0].cidr_block
    destination_type = "SERVICE_CIDR_BLOCK"
    stateless        = false
    description      = "Control plane to OCI Services Network"

    tcp_options {
      min = 443
      max = 443
    }
  }

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# B. Public Load Balancer Security List
resource "oci_core_security_list" "lb" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-lb-sl"

  # Ingress: HTTP (80)
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    description = "Allow inbound HTTP"

    tcp_options {
      min = 80
      max = 80
    }
  }

  # Ingress: HTTPS (443)
  ingress_security_rules {
    protocol    = "6"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    description = "Allow inbound HTTPS"

    tcp_options {
      min = 443
      max = 443
    }
  }

  # Egress: Route traffic to worker nodes on NodePort range (30000-32767)
  egress_security_rules {
    protocol         = "6"
    destination      = var.nodes_subnet_cidr
    destination_type = "CIDR_BLOCK"
    stateless        = false
    description      = "Load Balancer to Worker Nodes NodePort range"

    tcp_options {
      min = 30000
      max = 32767
    }
  }

  # Egress: Ingress controller health checks (10254)
  egress_security_rules {
    protocol         = "6"
    destination      = var.nodes_subnet_cidr
    destination_type = "CIDR_BLOCK"
    stateless        = false
    description      = "Ingress Controller health checks"

    tcp_options {
      min = 10254
      max = 10254
    }
  }

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# C. Private Worker Nodes Security List
resource "oci_core_security_list" "nodes" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "${var.prefix}-nodes-sl"

  # Ingress: Inter-node communication (Pod-to-Pod and Flannel VxLAN)
  ingress_security_rules {
    protocol    = "all"
    source      = var.nodes_subnet_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false
    description = "Allow all inter-node traffic"
  }

  # Ingress: Control plane to kubelet (10250)
  ingress_security_rules {
    protocol    = "6"
    source      = var.k8s_api_subnet_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false
    description = "Control plane to kubelet"

    tcp_options {
      min = 10250
      max = 10250
    }
  }

  # Ingress: Load Balancer to NodePort (30000-32767)
  ingress_security_rules {
    protocol    = "6"
    source      = var.lb_subnet_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false
    description = "Load balancer to worker node NodePorts"

    tcp_options {
      min = 30000
      max = 32767
    }
  }

  # Ingress: Load Balancer to Ingress Controller health checks (10254)
  ingress_security_rules {
    protocol    = "6"
    source      = var.lb_subnet_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false
    description = "Load balancer to ingress health check"

    tcp_options {
      min = 10254
      max = 10254
    }
  }

  # Ingress: ICMP Path MTU Discovery
  ingress_security_rules {
    protocol    = "1"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false
    description = "ICMP Path MTU discovery"

    icmp_options {
      type = 3
      code = 4
    }
  }

  # Egress: All outbound traffic (via NAT GW to internet, Service GW to OSN)
  egress_security_rules {
    protocol         = "all"
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    stateless        = false
    description      = "Allow all outbound traffic"
  }

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

# 5. Subnets
resource "oci_core_subnet" "k8s_api" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.k8s_api_subnet_cidr
  display_name               = "${var.prefix}-k8s-api-subnet"
  dns_label                  = "k8sapi"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.k8s_api.id]
  prohibit_public_ip_on_vnic = false

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

resource "oci_core_subnet" "lb" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.lb_subnet_cidr
  display_name               = "${var.prefix}-lb-subnet"
  dns_label                  = "lb"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.lb.id]
  prohibit_public_ip_on_vnic = false

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}

resource "oci_core_subnet" "nodes" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.nodes_subnet_cidr
  display_name               = "${var.prefix}-nodes-subnet"
  dns_label                  = "nodes"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.nodes.id]
  prohibit_public_ip_on_vnic = true

  freeform_tags = {
    "Project"   = "SportsAgentic"
    "ManagedBy" = "OpenTofu"
  }
}
