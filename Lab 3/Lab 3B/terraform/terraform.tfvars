# Enable full teardown of S3 buckets
allow_teardown = true
# Tokyo state vars
saopaulo_vpc_cidr = "10.1.0.0/16"

# Sao Paulo TGW ID (optional)
# - If left null, the Tokyo stack will auto-read it from ./saopaulo/terraform.tfstate
#   after the Sao Paulo stack has been applied.
saopaulo_tgw_id = null

# Sao Paulo account ID (set after Sao Paulo apply)
saopaulo_account_id = "198547498722"

# Toggle TGW peering from Tokyo once Sao Paulo is ready
enable_saopaulo_tgw_peering = true

