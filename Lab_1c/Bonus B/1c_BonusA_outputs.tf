output "bonusA_ec2_instance_id" {
	description = "EC2 instance ID (used for Session Manager verification)"
	value       = aws_instance.chrisbarm_ec2_01.id
}

output "bonusA_ec2_public_ip" {
	description = "EC2 public IP (should be null for Bonus-A)"
	value       = aws_instance.chrisbarm_ec2_01.public_ip
}

output "bonusA_interface_endpoint_services" {
	description = "Interface VPC endpoint service names created for Bonus-A"
	value       = [for ep in aws_vpc_endpoint.chrisbarm_interface_endpoints : ep.service_name]
}

output "bonusA_s3_gateway_endpoint_id" {
	description = "S3 Gateway VPC endpoint ID"
	value       = aws_vpc_endpoint.chrisbarm_s3_gateway_endpoint.id
}


## Added a NAT gateway and a private route so the private EC2 instance can install packages while
## staying private.  This keeps Bonus A endpoints and avoids the user-data install failure.

