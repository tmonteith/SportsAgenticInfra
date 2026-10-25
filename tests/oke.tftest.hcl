mock_provider "oci" {
  mock_data "oci_identity_availability_domains" {
    defaults = {
      availability_domains = [
        {
          compartment_id = "ocid1.tenancy.oc1..test"
          id             = "ocid1.ad.oc1..test1"
          name           = "Uwhm:US-ASHBURN-AD-1"
        }
      ]
    }
  }

  mock_data "oci_containerengine_node_pool_option" {
    defaults = {
      sources = [
        {
          image_id    = "ocid1.image.oc1.iad.arm-test-image"
          source_name = "Oracle-Linux-8.10-aarch64-2024.08.31-0-OKE-1.34.0-1"
          source_type = "IMAGE"
        }
      ]
    }
  }

  mock_data "oci_containerengine_cluster_kube_config" {
    defaults = {
      content = <<-EOT
        apiVersion: v1
        clusters:
        - cluster:
            certificate-authority-data: dGVzdC1jYS1kYXRh
            server: https://129.146.0.1:6443
          name: cluster
        contexts:
        - context:
            cluster: cluster
            user: user
          name: context
        current-context: context
        kind: Config
        preferences: {}
        users:
        - name: user
          user:
            token: test-token
      EOT
    }
  }
}

run "test_oke_module" {
  command = plan

  module {
    source = "./modules/oke"
  }

  variables {
    tenancy_ocid             = "ocid1.tenancy.oc1..test"
    compartment_id           = "ocid1.compartment.oc1..test"
    prefix                   = "sportsagentic"
    vcn_id                   = "ocid1.vcn.oc1..test"
    k8s_api_subnet_id        = "ocid1.subnet.oc1..api"
    lb_subnet_id             = "ocid1.subnet.oc1..lb"
    nodes_subnet_id          = "ocid1.subnet.oc1..nodes"
    cluster_type             = "BASIC_CLUSTER"
    k8s_version              = "v1.34.10"
    node_shape               = "VM.Standard.A1.Flex"
    model_pool_size          = 1
    model_pool_ocpus         = 4
    model_pool_memory_in_gbs = 24
  }

  # Cluster control plane assertions
  assert {
    condition     = oci_containerengine_cluster.main.type == "BASIC_CLUSTER"
    error_message = "OKE cluster type must be BASIC_CLUSTER"
  }

  assert {
    condition     = oci_containerengine_cluster.main.kubernetes_version == "v1.34.10"
    error_message = "Kubernetes version must be v1.34.10"
  }

  assert {
    condition     = oci_containerengine_cluster.main.cluster_pod_network_options[0].cni_type == "FLANNEL_OVERLAY"
    error_message = "Cluster pod networking must use FLANNEL_OVERLAY"
  }

  # Single Node Pool assertions
  assert {
    condition     = oci_containerengine_node_pool.model.node_shape == "VM.Standard.A1.Flex"
    error_message = "Model node pool must use ARM VM.Standard.A1.Flex"
  }

  assert {
    condition     = oci_containerengine_node_pool.model.node_shape_config[0].ocpus == 4
    error_message = "Model node pool must be configured with 4 OCPUs"
  }

  assert {
    condition     = oci_containerengine_node_pool.model.node_shape_config[0].memory_in_gbs == 24
    error_message = "Model node pool must be configured with 24 GB RAM"
  }

  assert {
    condition     = oci_containerengine_node_pool.model.node_config_details[0].size == 1
    error_message = "Single node pool size must be 1"
  }
}
