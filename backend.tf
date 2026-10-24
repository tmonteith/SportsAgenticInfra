terraform {
  backend "s3" {
    bucket                      = "sportsagentic-tfstate"
    key                         = "infra/sportsagentic.tfstate"
    region                      = "us-chicago-1"
    endpoint                    = "https://<namespace>.compat.objectstorage.us-chicago-1.oraclecloud.com"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
    use_lockfile                = false
  }
}

