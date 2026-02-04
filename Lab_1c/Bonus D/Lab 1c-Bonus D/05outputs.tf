output "chrisbarm_vpc_id" {
  value = aws_vpc.chrisbarm_vpc01.id
}

output "chrisbarm_public_subnet_ids" {
  value = aws_subnet.chrisbarm_public_subnets[*].id
}

output "chrisbarm_private_subnet_ids" {
  value = aws_subnet.chrisbarm_private_subnets[*].id
}

output "lab_ec2_public_ip" {
  value = aws_instance.chrisbarm_ec2_01.public_ip
}

output "lab_ec2_public_dns" {
  value = aws_instance.chrisbarm_ec2_01.public_dns
}

output "lab_rds_endpoint" {
  value = aws_db_instance.chrisbarm_rds01.address
}

output "lab_secret_name" {
  value = aws_secretsmanager_secret.chrisbarm_db_secret01.name
}

output "lab_secret_arn" {
  value = aws_secretsmanager_secret.chrisbarm_db_secret01.arn
}