package test

import (
	"os"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestPlatformPlan verifies that the Platform module plans without syntax errors.
func TestPlatformPlan(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		TerraformDir:    "../modules/platform",
		TerraformBinary: "tofu",
		Vars: map[string]interface{}{
			"tenancy_ocid":                 getEnv("OCI_TENANCY_OCID", "ocid1.tenancy.oc1..test"),
			"compartment_id":               getEnv("OCI_COMPARTMENT_OCID", "ocid1.compartment.oc1..test"),
			"prefix":                       "sportsagentic-test",
			"lb_subnet_id":                 "ocid1.subnet.oc1..lb",
			"domain_name":                  "sportagentic.dev",
			"mcp_nodes_dynamic_group_name": "sportsagentic-mcp-nodes-dg",
		},
		NoColor: true,
	}

	planExitCode := terraform.InitAndPlanWithExitCode(t, terraformOptions)
	assert.True(t, planExitCode == 0 || planExitCode == 2, "Expected successful plan exit code")
}

// TestPlatformIntegration verifies NoSQL table, OCIR repos, and DNS nameservers against live infrastructure.
// Skipped unless RUN_INTEGRATION_TESTS=true is set.
func TestPlatformIntegration(t *testing.T) {
	if os.Getenv("RUN_INTEGRATION_TESTS") != "true" {
		t.Skip("Skipping live integration test. Set RUN_INTEGRATION_TESTS=true to run against live OCI.")
	}

	t.Parallel()

	terraformOptions := createBaseTerraformOptions(t, "..", nil)

	defer terraform.Destroy(t, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)

	tableName := terraform.Output(t, terraformOptions, "nosql_table_name")
	assert.Equal(t, "sportsagentic_cfb", tableName)

	tableID := terraform.Output(t, terraformOptions, "nosql_table_id")
	assert.NotEmpty(t, tableID)

	dnsZoneName := terraform.Output(t, terraformOptions, "dns_zone_name")
	assert.Equal(t, "sportagentic.dev", dnsZoneName)

	dnsNameservers := terraform.OutputList(t, terraformOptions, "dns_nameservers")
	assert.GreaterOrEqual(t, len(dnsNameservers), 2, "Expected at least 2 authoritative nameservers")

	ocirRegistryURL := terraform.Output(t, terraformOptions, "ocir_registry_url")
	assert.Contains(t, ocirRegistryURL, ".ocir.io")
}
