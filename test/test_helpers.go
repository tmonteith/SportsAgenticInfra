package test

import (
	"os"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
)

// getEnv returns the value of an environment variable or a fallback default.
func getEnv(key, fallback string) string {
	if value, exists := os.LookupEnv(key); exists && strings.TrimSpace(value) != "" {
		return value
	}
	return fallback
}

// createBaseTerraformOptions configures Terratest to use OpenTofu (tofu) and passes standard variables.
func createBaseTerraformOptions(t *testing.T, terraformDir string, extraVars map[string]interface{}) *terraform.Options {
	vars := map[string]interface{}{
		"tenancy_ocid":   getEnv("OCI_TENANCY_OCID", "ocid1.tenancy.oc1..test"),
		"compartment_id": getEnv("OCI_COMPARTMENT_OCID", "ocid1.compartment.oc1..test"),
		"region":         getEnv("OCI_REGION", "us-ashburn-1"),
		"prefix":         "sportsagentic-test",
		"cluster_type":   "BASIC_CLUSTER",
		"domain_name":    "sportagentic.dev",
	}

	for k, v := range extraVars {
		vars[k] = v
	}

	return &terraform.Options{
		TerraformDir:    terraformDir,
		TerraformBinary: "tofu",
		Vars:            vars,
		NoColor:         true,
	}
}
