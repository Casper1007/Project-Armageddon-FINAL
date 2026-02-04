# EC2 → RDS Lab - Quick Reference Commands

## Get Your Infrastructure Details

```bash
# Get EC2 instance information
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=chrisbarm-ec2_01" \
  --region us-east-1 \
  --query "Reservations[].Instances[].[InstanceId,PublicIpAddress,State.Name]" \
  --output text

# Example output:
# i-061b663d2d9d6ff80  54.91.122.42  running
```

```bash
# Get RDS endpoint
aws rds describe-db-instances \
  --db-instance-identifier chrisbarm-rds01 \
  --region us-east-1 \
  --query "DBInstances[0].Endpoint" \
  --output text

# Example output:
# chrisbarm-rds01.c4x68420cyvy.us-east-1.rds.amazonaws.com:3306
```

## Verification Commands (From Lab Requirements)

### 6.1 - Verify EC2 Instance

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=chrisbarm-ec2_01" \
  --region us-east-1 \
  --query "Reservations[].Instances[].[InstanceId,State.Name]"
```

### 6.2 - Verify IAM Role

```bash
aws ec2 describe-instances \
  --instance-ids i-061b663d2d9d6ff80 \
  --region us-east-1 \
  --query "Reservations[].Instances[].IamInstanceProfile.Arn"
```

### 6.3 - Verify RDS Status

```bash
aws rds describe-db-instances \
  --db-instance-identifier chrisbarm-rds01 \
  --region us-east-1 \
  --query "DBInstances[0].DBInstanceStatus"
```

### 6.4 - Verify RDS Endpoint

```bash
aws rds describe-db-instances \
  --db-instance-identifier chrisbarm-rds01 \
  --region us-east-1 \
  --query "DBInstances[0].Endpoint"
```

### 6.5 - Verify Security Group Rules

```bash
# Get RDS security group
RDS_SG=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=chrisbarm-rds-sg01" \
  --region us-east-1 \
  --query "SecurityGroups[0].GroupId" \
  --output text)

# Get EC2 security group
EC2_SG=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=chrisbarm-ec2-sg01" \
  --region us-east-1 \
  --query "SecurityGroups[0].GroupId" \
  --output text)

# Verify MySQL rule (should reference EC2_SG, NOT 0.0.0.0/0)
aws ec2 describe-security-groups \
  --group-ids "$RDS_SG" \
  --region us-east-1 \
  --query "SecurityGroups[0].IpPermissions" \
  --output table
```

### 6.6 - Verify Secrets Manager Access

```bash
# From your EC2 instance, retrieve the secret:
aws secretsmanager get-secret-value \
  --secret-id lab1a/rds/mysql \
  --region us-east-1

# If this succeeds, EC2 can access Secrets Manager ✅
# If this fails with AccessDenied, IAM role is misconfigured ❌
```

### 6.7 - Verify Database Connectivity

```bash
# From EC2 instance SSH session:

# Install MySQL client
sudo apt-get update && sudo apt-get install -y mysql-client

# Get credentials from Secrets Manager
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id lab1a/rds/mysql \
  --region us-east-1 \
  --query SecretString \
  --output text)

# Extract values
DB_HOST=$(echo "$SECRET" | jq -r '.host')
DB_USER=$(echo "$SECRET" | jq -r '.username')
DB_PASS=$(echo "$SECRET" | jq -r '.password')
DB_NAME=$(echo "$SECRET" | jq -r '.dbname')

# Connect to database
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES;"
```

### 6.8 - Verify End-to-End Data Path

```bash
# Get EC2 public IP
EC2_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=chrisbarm-ec2_01" \
  --region us-east-1 \
  --query "Reservations[].Instances[0].PublicIpAddress" \
  --output text)

# Initialize database
curl -X POST "http://${EC2_IP}/init"

# Add a note
curl "http://${EC2_IP}/add?note=cloud_labs_are_real"

# List notes
curl "http://${EC2_IP}/list" | jq .

# Expected: Notes persist and show in /list output
```

## Terraform Commands

```bash
# Validate Terraform files
terraform validate

# Plan changes (don't apply)
terraform plan

# Apply changes
terraform apply

# See current state
terraform state list
terraform state show aws_instance.chrisbarm_ec2_01
terraform state show aws_db_instance.chrisbarm_rds01

# Refresh state from AWS
terraform refresh

# Get outputs
terraform output
terraform output -raw chrisbarm_rds_endpoint
```

## Useful One-Liners

```bash
# Get EC2 public IP quickly
aws ec2 describe-instances --filters "Name=tag:Name,Values=chrisbarm-ec2_01" --region us-east-1 --query "Reservations[0].Instances[0].PublicIpAddress" --output text

# Get RDS endpoint quickly
aws rds describe-db-instances --db-instance-identifier chrisbarm-rds01 --region us-east-1 --query "DBInstances[0].Endpoint.Address" --output text

# Get current RDS status
aws rds describe-db-instances --db-instance-identifier chrisbarm-rds01 --region us-east-1 --query "DBInstances[0].DBInstanceStatus" --output text

# Check if RDS is publicly accessible (should be False!)
aws rds describe-db-instances --db-instance-identifier chrisbarm-rds01 --region us-east-1 --query "DBInstances[0].PubliclyAccessible" --output text

# List all resources in Terraform state
terraform state list | sort
```

## Debugging Commands

```bash
# Check EC2 user-data execution (from EC2 SSH)
sudo tail -100 /var/log/rds-app.log
sudo tail -100 /var/log/app-startup.log

# Check if Flask app is running
ps aux | grep python

# Check if port 80 is listening
netstat -tuln | grep 80  # or: ss -tuln | grep 80

# Test network connectivity to RDS from EC2
nc -zv chrisbarm-rds01.c4x68420cyvy.us-east-1.rds.amazonaws.com 3306

# Check security group rules
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=sg-07b6f3b0c45df9bd2" \
  --region us-east-1 \
  --output table
```

## Common Test Sequences

### Full Verification Flow

```bash
#!/bin/bash

echo "1. Checking EC2..."
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=chrisbarm-ec2_01" \
  --region us-east-1 \
  --query "Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]" \
  --output table

echo ""
echo "2. Checking RDS..."
aws rds describe-db-instances \
  --db-instance-identifier chrisbarm-rds01 \
  --region us-east-1 \
  --query "DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,Endpoint.Address]" \
  --output table

echo ""
echo "3. Checking IAM Role..."
aws ec2 describe-instances \
  --instance-ids i-061b663d2d9d6ff80 \
  --region us-east-1 \
  --query "Reservations[].Instances[].IamInstanceProfile.Arn" \
  --output text

echo ""
echo "4. Checking Secrets..."
aws secretsmanager get-secret-value \
  --secret-id lab1a/rds/mysql \
  --region us-east-1 \
  --query 'SecretString' | jq .

echo ""
echo "5. Checking Security Groups..."
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=chrisbarm-rds-sg01" \
  --region us-east-1 \
  --query "SecurityGroups[0].IpPermissions" \
  --output table
```

## Application Endpoints

Once running, the Flask app provides:

```bash
# Get help
curl http://54.91.122.42/

# Initialize database
curl -X POST http://54.91.122.42/init

# Add a note
curl "http://54.91.122.42/add?note=my_note_text"

# List notes
curl http://54.91.122.42/list

# Health check
curl http://54.91.122.42/health
```

## Credentials Location

```bash
# EC2 credentials (obtained automatically via IAM role)
# AWS SDK reads from:
# $AWS_ROLE_ARN
# $AWS_WEB_IDENTITY_TOKEN_FILE
# OR from EC2 metadata service at:
# http://169.254.169.254/latest/meta-data/

# Database credentials (stored in Secrets Manager)
# Retrieved by application via:
aws secretsmanager get-secret-value --secret-id lab1a/rds/mysql

# Credentials output:
{
  "username": "admin",
  "password": "<PASSWORD>",
  "host": "chrisbarm-rds01.c4x68420cyvy.us-east-1.rds.amazonaws.com",
  "port": 3306,
  "dbname": "labdb"
}
```

## Quick Status Check

```bash
# One command to check everything
(echo "EC2:" && aws ec2 describe-instances --filters "Name=tag:Name,Values=chrisbarm-ec2_01" --region us-east-1 --query "Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress]" --output text) && \
(echo "RDS:" && aws rds describe-db-instances --db-instance-identifier chrisbarm-rds01 --region us-east-1 --query "DBInstances[0].[DBInstanceStatus,Endpoint.Address]" --output text) && \
(echo "App:" && curl -s http://$(aws ec2 describe-instances --filters "Name=tag:Name,Values=chrisbarm-ec2_01" --region us-east-1 --query "Reservations[0].Instances[0].PublicIpAddress" --output text)/ | jq -r '.status')
```

---

## Variables Reference

| Variable | Value |
|----------|-------|
| Region | us-east-1 |
| Project Name | chrisbarm |
| VPC CIDR | 10.0.0.0/16 |
| EC2 Instance ID | i-061b663d2d9d6ff80 |
| EC2 Public IP | 54.91.122.42 |
| RDS Identifier | chrisbarm-rds01 |
| RDS Endpoint | chrisbarm-rds01.c4x68420cyvy.us-east-1.rds.amazonaws.com |
| DB Name | labdb |
| DB User | admin |
| Secret ID | lab1a/rds/mysql |
| Account ID | 198547498722 |

---

**Remember**: Save these commands for future reference!
