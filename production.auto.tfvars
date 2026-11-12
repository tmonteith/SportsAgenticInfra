# Non-secret production settings, committed so CI plans the same infrastructure
# as a local apply. Credentials and the applying user's email stay in
# terraform.tfvars locally and in GitHub secrets for CI.
#
# OpenTofu loads *.auto.tfvars after terraform.tfvars, so these values win.
# Change them here, not in terraform.tfvars.

compartment_name = "sportsagentic-1"

# Lakehouse extractor and poller images in OCIR: the short SHA of the SportsAgenticLakehouse
# commit whose ingest-images workflow pushed them. "" uninstalls the ingest release.
ingest_image_tag = "58743db"

# E5 is an x86 shape outside the Always Free allowance, so this node is billed.
node_shape         = "VM.Standard.E5.Flex"
node_fault_domains = ["FAULT-DOMAIN-1", "FAULT-DOMAIN-2", "FAULT-DOMAIN-3"]

# Memory budget and how a change reaches the running node: docs/data-platform.md.
model_pool_size          = 1
model_pool_ocpus         = 1
model_pool_memory_in_gbs = 12

# GCP project that holds the lakehouse (gcp/ stack). Not a secret.
gcp_project_id = "sports-agent-511915"

# Keep the node in the AD that holds its block volumes (llama models, Kafka, Airflow
# Postgres). Volumes cannot follow a node to another AD.
node_availability_domain = "AD-3"
