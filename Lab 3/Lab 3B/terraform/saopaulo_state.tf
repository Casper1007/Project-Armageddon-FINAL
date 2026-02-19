############################################
# Sao Paulo local state (optional)
############################################

# This lets the Tokyo stack automatically pick up the Sao Paulo TGW ID after
# the Sao Paulo stack has been applied locally in ./saopaulo.
data "terraform_remote_state" "saopaulo_local" {
  count   = fileexists("${path.module}/saopaulo/terraform.tfstate") ? 1 : 0
  backend = "local"

  config = {
    path = "${path.module}/saopaulo/terraform.tfstate"
  }
}

locals {
  resolved_saopaulo_tgw_id = try(
    coalesce(
      var.saopaulo_tgw_id,
      try(data.terraform_remote_state.saopaulo_local[0].outputs.saopaulo_tgw_id, null)
    ),
    null
  )

  resolved_saopaulo_account_id = coalesce(
    var.saopaulo_account_id,
    data.aws_caller_identity.current.account_id
  )
}

# Validation: fail with a clear error if neither is set
resource "null_resource" "validate_saopaulo_tgw_id" {
  count = local.resolved_saopaulo_tgw_id == null ? 1 : 0
  provisioner "local-exec" {
    command = "echo 'ERROR: Sao Paulo TGW ID is missing. Set var.saopaulo_tgw_id or apply the Sao Paulo stack to generate the output.' && exit 1"
  }
}
