output "saopaulo_tgw_id" {
  description = "Sao Paulo Transit Gateway ID for cross-region peering"
  value       = aws_ec2_transit_gateway.liberdade_tgw01.id
}

output "tokyo_tgw_peering_attachment_state" {
  description = "State of the TGW peering attachment as seen from Sao Paulo (null when no attachment ID provided)."
  value       = local.liberdade_peer_state
}

output "tokyo_tgw_peering_attachment_available" {
  description = "Whether the TGW peering attachment is available (true means routes/propagation can be created)."
  value       = local.liberdade_peer_available
}
