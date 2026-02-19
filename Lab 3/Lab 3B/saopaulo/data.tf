# Reads outputs from the Tokyo (shinjuku) Terraform state for cross-region wiring
# Set use_tokyo_remote_state = true only when S3 access is available.

data "terraform_remote_state" "tokyo" {
  count   = var.use_tokyo_remote_state ? 1 : 0
  backend = "s3"
  config = {
    bucket = var.tokyo_state_bucket
    key    = var.tokyo_state_key
    region = var.tokyo_state_region
  }
}

# Local fallback: read Tokyo outputs from the sibling stack's local state file.
# This avoids manual copy/paste of the TGW peering attachment ID during the lab.
data "terraform_remote_state" "tokyo_local" {
  count   = var.use_tokyo_remote_state ? 0 : (fileexists("${path.module}/../terraform.tfstate") ? 1 : 0)
  backend = "local"
  config = {
    path = "${path.module}/../terraform.tfstate"
  }
}

locals {
  tokyo_vpc_cidr     = var.use_tokyo_remote_state ? data.terraform_remote_state.tokyo[0].outputs.tokyo_vpc_cidr : var.tokyo_vpc_cidr
  tokyo_rds_endpoint = var.use_tokyo_remote_state ? data.terraform_remote_state.tokyo[0].outputs.tokyo_rds_endpoint : var.tokyo_rds_endpoint
  tokyo_rds_port     = var.use_tokyo_remote_state ? try(data.terraform_remote_state.tokyo[0].outputs.tokyo_rds_port, 3306) : var.tokyo_rds_port

  tokyo_tgw_peering_attachment_id = try(
    coalesce(
      var.tokyo_tgw_peering_attachment_id,
      try(data.terraform_remote_state.tokyo[0].outputs.tokyo_tgw_peering_attachment_id, null),
      try(data.terraform_remote_state.tokyo_local[0].outputs.tokyo_tgw_peering_attachment_id, null)
    ),
    null
  )
}
