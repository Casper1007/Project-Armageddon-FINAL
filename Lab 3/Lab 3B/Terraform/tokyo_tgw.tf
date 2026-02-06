# Get current AWS account ID for peering
data "aws_caller_identity" "current" {}

# Explanation: Shinjuku Station is the hub—Tokyo is the data authority.
resource "aws_ec2_transit_gateway" "shinjuku_tgw01" {
  description = "shinjuku-tgw01 (Tokyo hub)"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  tags        = { Name = "shinjuku-tgw01" }
}

resource "aws_ec2_transit_gateway_route_table" "shinjuku_tgw_rt01" {
  transit_gateway_id = aws_ec2_transit_gateway.shinjuku_tgw01.id
  tags               = { Name = "shinjuku-tgw-rt01" }
}

# Explanation: Shinjuku connects to the Tokyo VPC—this is the gate to the medical records vault.
resource "aws_ec2_transit_gateway_vpc_attachment" "shinjuku_attach_tokyo_vpc01" {
  transit_gateway_id = aws_ec2_transit_gateway.shinjuku_tgw01.id
  vpc_id             = aws_vpc.chrisbarm_vpc01.id
  subnet_ids         = [aws_subnet.chrisbarm_private_subnets[0].id, aws_subnet.chrisbarm_private_subnets[1].id]
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  tags               = { Name = "shinjuku-attach-tokyo-vpc01" }
}

resource "aws_ec2_transit_gateway_route_table_association" "shinjuku_vpc_assoc01" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shinjuku_attach_tokyo_vpc01.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shinjuku_tgw_rt01.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "shinjuku_vpc_prop01" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shinjuku_attach_tokyo_vpc01.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shinjuku_tgw_rt01.id
}

# Explanation: Shinjuku opens a corridor request to Liberdade—compute may travel, data may not.
resource "aws_ec2_transit_gateway_peering_attachment" "shinjuku_to_liberdade_peer01" {
  count                   = var.saopaulo_tgw_id == null ? 0 : 1
  transit_gateway_id      = aws_ec2_transit_gateway.shinjuku_tgw01.id
  peer_account_id         = data.aws_caller_identity.current.account_id
  peer_region             = "sa-east-1"
  peer_transit_gateway_id = var.saopaulo_tgw_id # set from Sao Paulo state output
  tags                    = { Name = "shinjuku-to-liberdade-peer01" }
}

# Accept the corridor request in the peer region (Liberdade / Sao Paulo) so the
# peering attachment is in an "available" state before association/routes.
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "liberdade_accept_shinjuku_peer01" {
  count                         = var.saopaulo_tgw_id == null ? 0 : 1
  provider                      = aws.saopaulo
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.shinjuku_to_liberdade_peer01[0].id
  tags                          = { Name = "liberdade-accept-shinjuku-peer01" }
}

resource "aws_ec2_transit_gateway_route_table_association" "shinjuku_peer_assoc01" {
  count                          = var.saopaulo_tgw_id == null ? 0 : 1
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.shinjuku_to_liberdade_peer01[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shinjuku_tgw_rt01.id
  
  # Wait for peering to be accepted before associating
  depends_on = [aws_ec2_transit_gateway_peering_attachment_accepter.liberdade_accept_shinjuku_peer01]
}

# NOTE: Propagation is NOT supported for peering attachments - AWS limitation
# Static routes must be used instead (see shinjuku_to_liberdade_tgw_route01 below)

resource "aws_ec2_transit_gateway_route" "shinjuku_to_liberdade_tgw_route01" {
  count                          = var.saopaulo_tgw_id == null ? 0 : 1
  destination_cidr_block         = var.saopaulo_vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.shinjuku_to_liberdade_peer01[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shinjuku_tgw_rt01.id
  
  # Ensure peering is accepted and associated before creating routes
  depends_on = [
    aws_ec2_transit_gateway_peering_attachment_accepter.liberdade_accept_shinjuku_peer01,
    aws_ec2_transit_gateway_route_table_association.shinjuku_peer_assoc01
  ]
}
