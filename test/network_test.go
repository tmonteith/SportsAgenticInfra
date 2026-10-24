package test

import (
	"os"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestNetworkPlan verifies that the Network module plans without errors.
func TestNetworkPlan(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		TerraformDir:    "../modules/network",
		TerraformBinary: "tofu",
		Vars: map[string]interface{}{
			"compartment_id": getEnv("OCI_COMPARTMENT_OCID", "ocid1.compartment.oc1..test"),
			"prefix":         "sportsagentic-test",
		},
		NoColor: true,
	}

	planExitCode := terraform.InitAndPlanWithExitCode(t, terraformOptions)
	// Plan exit code 0 or 2 (success with changes)
	assert.True(t, planExitCode == 0 || planExitCode == 2, "Expected successful plan exit code")
}

// TestNetworkIntegration applies the network module against real OCI infrastructure and tears it down.
// Skipped unless RUN_INTEGRATION_TESTS=true is set.
func TestNetworkIntegration(t *testing.T) {
	if os.Getenv("RUN_INTEGRATION_TESTS") != "true" {
		t.Skip("Skipping live integration test. Set RUN_INTEGRATION_TESTS=true to run against live OCI.")
	}

	t.Parallel()

	terraformOptions := &terraform.Options{
		TerraformDir:    "../modules/network",
		TerraformBinary: "tofu",
		Vars: map[string]interface{}{
			"compartment_id": getEnv("OCI_COMPARTMENT_OCID", ""),
			"prefix":         "satest-net",
		},
		NoColor: true,
	}

	defer terraform.Destroy(t, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)

	vcnID := terraform.Output(t, terraformOptions, "vcn_id")
	assert.NotEmpty(t, vcnID, "VCN OCID should not be empty")
	assert.Contains(t, vcnID, "ocid1.vcn.", "VCN OCID should be valid format")

	nodesSubnetID := terraform.Output(t, terraformOptions, "nodes_subnet_id")
	assert.NotEmpty(t, nodesSubnetID, "Nodes subnet OCID should not be empty")

	lbSubnetID := terraform.Output(t, terraformOptions, "lb_subnet_id")
	assert.NotEmpty(t, lbSubnetID, "LB subnet OCID should not be empty")
}
