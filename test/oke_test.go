package test

import (
	"os"
	"testing"

	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestOkeClusterPlan verifies that the OKE module plans correctly.
func TestOkeClusterPlan(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		TerraformDir:    "../modules/oke",
		TerraformBinary: "tofu",
		Vars: map[string]interface{}{
			"tenancy_ocid":      getEnv("OCI_TENANCY_OCID", "ocid1.tenancy.oc1..test"),
			"compartment_id":    getEnv("OCI_COMPARTMENT_OCID", "ocid1.compartment.oc1..test"),
			"prefix":            "sportsagentic-test",
			"vcn_id":            "ocid1.vcn.oc1..test",
			"k8s_api_subnet_id": "ocid1.subnet.oc1..api",
			"lb_subnet_id":      "ocid1.subnet.oc1..lb",
			"nodes_subnet_id":   "ocid1.subnet.oc1..nodes",
			"cluster_type":      "BASIC_CLUSTER",
			"k8s_version":       "v1.34.0",
		},
		NoColor: true,
	}

	planExitCode := terraform.InitAndPlanWithExitCode(t, terraformOptions)
	assert.True(t, planExitCode == 0 || planExitCode == 2, "Expected successful plan exit code")
}

// TestOkeClusterIntegration applies the cluster and verifies kubectl connectivity and node pools.
// Skipped unless RUN_INTEGRATION_TESTS=true is set.
func TestOkeClusterIntegration(t *testing.T) {
	if os.Getenv("RUN_INTEGRATION_TESTS") != "true" {
		t.Skip("Skipping live integration test. Set RUN_INTEGRATION_TESTS=true to run against live OCI.")
	}

	t.Parallel()

	terraformOptions := createBaseTerraformOptions(t, "..", nil)

	defer terraform.Destroy(t, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)

	clusterID := terraform.Output(t, terraformOptions, "oke_cluster_id")
	assert.NotEmpty(t, clusterID)

	// Write kubeconfig to temp file to test kubectl connectivity
	kubeconfig := terraform.Output(t, terraformOptions, "kubeconfig")
	kubeconfigPath := "/tmp/test-kubeconfig"
	err := os.WriteFile(kubeconfigPath, []byte(kubeconfig), 0600)
	assert.NoError(t, err)
	defer os.Remove(kubeconfigPath)

	kubectlOptions := k8s.NewKubectlOptions("", kubeconfigPath, "default")
	nodes := k8s.GetNodes(t, kubectlOptions)
	assert.GreaterOrEqual(t, len(nodes), 1, "Expected at least 1 node in services pool")
}
