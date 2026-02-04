# Bonus A: Private Compute with VPC Endpoints & SSM Session Manager

## Overview

This architecture implements **secure private compute** that mirrors production practices in regulated industries (finance, healthcare, government). The design eliminates unnecessary internet exposure while maintaining full access to AWS control-plane services.

**Key Philosophy**: "Private by default, minimal IAM, leverage AWS APIs instead of internet."

---

## Design Goals ✅

| Goal | How It's Achieved |
|------|------------------|
| EC2 is private (no public IP) | `associate_public_ip_address = false` in instance config |
| No SSH required | Session Manager via SSM + VPC Endpoints |
| Private subnets don't need NAT for AWS APIs | VPC Interface Endpoints for SSM, Logs, Secrets Manager, KMS |
| S3 access without NAT | S3 Gateway Endpoint + route table integration |
| Least-privilege IAM | Scoped policies: specific secrets, parameter paths, log groups |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        VPC (10.0.0.0/16)                    │
│                                                              │
│  ┌──────────────────────┐      ┌──────────────────────┐     │
│  │ Public Subnets       │      │ Private Subnets      │     │
│  │ (NAT Gateway here)   │      │ (EC2 + RDS here)     │     │
│  └──────────────────────┘      └──────────────────────┘     │
│          │                              │                    │
│          └──────► IGW ──────►           │                    │
│                                         │                    │
│              ┌─────────────────────────────────┐             │
│              │  VPC Interface Endpoints        │             │
│              │  (Private DNS enabled)          │             │
│              ├─────────────────────────────────┤             │
│              │ • SSM                           │             │
│              │ • EC2Messages                   │             │
│              │ • SSMMessages                   │             │
│              │ • CloudWatch Logs               │             │
│              │ • Secrets Manager               │             │
│              │ • KMS                           │             │
│              │ • S3 (Gateway)                  │             │
│              └─────────────────────────────────┘             │
│                         ▲                                     │
│                         │ (HTTPS only)                        │
│              ┌──────────┴──────────┐                          │
│              │ Private EC2 Instance│                          │
│              │  (Security Group)   │                          │
│              │  - No SSH           │                          │
│              │  - SSM Session Mgr  │                          │
│              │  - Scoped IAM Role  │                          │
│              └─────────────────────┘                          │
│                         │                                     │
│              ┌──────────▼──────────┐                          │
│              │   RDS in Private    │                          │
│              │   Subnet (MySQL)    │                          │
│              └─────────────────────┘                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Components

### 1. **VPC Infrastructure**
- **VPC**: `10.0.0.0/16`
- **Public Subnets**: `10.0.1.0/24`, `10.0.2.0/24` (NAT Gateway for Lab 1a)
- **Private Subnets**: `10.0.101.0/24`, `10.0.102.0/24` (Bonus A compute)
- **Availability Zones**: Spread across AZs for resilience

### 2. **VPC Endpoints** (Replace NAT for AWS APIs)

#### Interface Endpoints (HTTPS, Private DNS)
- **SSM** (`com.amazonaws.us-east-1.ssm`): Agent communication
- **EC2Messages** (`com.amazonaws.us-east-1.ec2messages`): Session Manager support
- **SSMMessages** (`com.amazonaws.us-east-1.ssmmessages`): Session Manager shell
- **CloudWatch Logs** (`com.amazonaws.us-east-1.logs`): Centralized log delivery
- **Secrets Manager** (`com.amazonaws.us-east-1.secretsmanager`): Credential retrieval
- **KMS** (`com.amazonaws.us-east-1.kms`): Encryption operations

**Security Group for Endpoints**:
- ✅ Inbound HTTPS (443) from private subnet CIDRs only
- ✅ Outbound: All (endpoints are receivers)

#### Gateway Endpoint (S3)
- **Service**: `com.amazonaws.us-east-1.s3`
- **Route**: Automatic injection into private route table
- **Use Cases**:
  - Package repo access (`s3://amazonlinux-repo`)
  - Golden AMI deployments
  - Data transfer to S3 buckets (no NAT needed)

### 3. **Security Groups**

#### Endpoints SG (`bonus-a-endpoints-sg`)
```
Inbound:  HTTPS (443) from 10.0.101.0/24, 10.0.102.0/24
Outbound: All (not used; endpoints receive only)
```

#### EC2 Instance SG (`bonus-a-ec2-sg`)
```
Inbound:  [None - Session Manager uses SSM, not SSH]
Outbound:
  - HTTPS (443) to Endpoints SG (for API calls)
  - MySQL (3306) to Lab 1a RDS via private subnet CIDR
```

### 4. **IAM Role: Least-Privilege Access**

#### Core Permissions
```
✅ SSM Session Manager (required)
   - ssmmessages:CreateControlChannel
   - ssmmessages:CreateDataChannel
   - ssmmessages:OpenControlChannel
   - ssmmessages:OpenDataChannel
   - ec2messages:* (5 actions)

✅ CloudWatch Logs (write only)
   Resource: arn:aws:logs:us-east-1:ACCOUNT:log-group:/aws/ec2/bonus-a-rds-app:*
   Actions: logs:CreateLogStream, logs:PutLogEvents, logs:DescribeLogStreams

✅ Secrets Manager (read specific secret)
   Resource: arn:aws:secretsmanager:us-east-1:ACCOUNT:secret:lab1a/rds/mysql*
   Action: secretsmanager:GetSecretValue

✅ Parameter Store (read /lab/* path only)
   Resource: arn:aws:ssm:us-east-1:ACCOUNT:parameter/lab/*
   Actions: ssm:GetParameter, ssm:GetParameters, ssm:GetParametersByPath
```

**What NOT to include**:
- ❌ `iam:*` (no credential escalation)
- ❌ `secretsmanager:GetSecretValue` on other secrets
- ❌ `ssm:PutParameter` (read-only for this instance)
- ❌ `s3:*` (no blanket S3 access; gates access by policy)

### 5. **Private EC2 Instance**

**Configuration** (in `bonus_a.tf`):
```hcl
resource "aws_instance" "bonus_a_ec2" {
  ami                         = "ami-0030e4319cbf4dbf2"  # Ubuntu 22.04 LTS
  instance_type               = var.ec2_instance_type
  subnet_id                   = local.private_subnet
  iam_instance_profile        = aws_iam_instance_profile.bonus_a_ec2_profile.name
  associate_public_ip_address = false  # 🔒 PRIVATE
  vpc_security_group_ids      = [aws_security_group.bonus_a_ec2_sg.id]
  user_data                   = file("${path.module}/1a_user_data.sh")
}
```

**Verification** (from instance):
```bash
# Confirm no public IP
curl -s http://169.254.169.254/latest/meta-data/public-ipv4
# Expected: (empty/error)

# Confirm private IP
curl -s http://169.254.169.254/latest/meta-data/local-ipv4
# Expected: 10.0.101.x or 10.0.102.x

# Confirm SSM agent is running
systemctl status snap.amazon-ssm-agent.amazon-ssm-agent
# Expected: active (running)
```

### 6. **CloudWatch Log Group**

```hcl
resource "aws_cloudwatch_log_group" "bonus_a_logs" {
  name              = "/aws/ec2/bonus-a-rds-app"
  retention_in_days = 7
}
```

**Log delivery flow**:
1. EC2 app writes logs to stdout/stderr
2. CloudWatch agent (or app) posts to `/aws/ec2/bonus-a-rds-app`
3. Via Logs VPC Endpoint (no NAT needed)
4. Logs retained 7 days, then deleted

---

## Real-World Alignment

| Concept | Company Practice | Why It Matters |
|---------|------------------|----------------|
| **Private Compute** | Banks, healthcare, gov don't allow EC2 with public IPs | Compliance (PCI-DSS, HIPAA, FedRAMP) |
| **VPC Endpoints** | Reduces NAT costs, eliminates internet exposure | Regulated orgs block egress to unknown IPs |
| **SSM Session Manager** | Replaces bastion/jump box + SSH keys | No key rotation, audit trail, IAM-native |
| **Least-Privilege IAM** | CIS Benchmarks, SOC2, ISO 27001 | Security interviews focus on this |
| **Parameter Store + Secrets Manager** | 12-factor app practices | Decoupled config from code |
| **CloudWatch Logs** | Central observability | Detect anomalies, comply with log retention rules |

---

## Terraform Modules & Dependencies

### Dependency Graph
```
VPC
├── Subnets (Public & Private)
├── Route Tables & Associations
├── Security Groups (Endpoints, EC2)
│   └── Depends on VPC ID
├── VPC Endpoints (Interface & Gateway)
│   └── Depend on Subnets & SG
└── EC2 Instance
    ├── Depends on VPC Endpoint readiness
    ├── Depends on IAM Role
    └── Depends on RDS (for connectivity)
```

### Key Files

| File | Purpose |
|------|---------|
| `bonus_a.tf` | Bonus A specific: endpoints, EC2, IAM, log group |
| `main.tf` | Lab 1a: VPC, subnets, routing, RDS, base IAM |
| `variables.tf` | Region, project name, CIDR blocks, DB config |
| `providers.tf` | AWS provider & region |
| `outputs.tf` | Lab 1a outputs |
| `1a_user_data.sh` | Init script for OS packages, DB setup |

---

## Deployment Steps

### 1. **Validate Variables**
```bash
cd /path/to/terraform_restart_fixed
cat terraform.tfvars  # or use -var flags
```

Ensure:
- `aws_region = "us-east-1"`
- `ec2_ami_id = "ami-0030e4319cbf4dbf2"` (or your Ubuntu 22.04 LTS AMI)
- `db_username`, `db_password` set (use `sensitive = true` in production)

### 2. **Plan & Review**
```bash
terraform plan -out=bonus_a.tfplan
```

Look for:
- 1x EC2 instance (private)
- 7x VPC endpoints
- 1x IAM role
- 1x CloudWatch log group
- Security groups with correct CIDR blocks

### 3. **Apply**
```bash
terraform apply bonus_a.tfplan
```

### 4. **Capture Outputs**
```bash
terraform output -json > outputs.json
```

**Key outputs to note**:
- `bonus_a_instance_id` → for Session Manager
- `bonus_a_instance_private_ip` → should be 10.0.x.x
- `bonus_a_instance_public_ip` → should be null
- `bonus_a_vpc_endpoints` → map of endpoint IDs

---

## Verification Checklist

### Phase 1: Infrastructure Exists
- [ ] EC2 instance is in private subnet
- [ ] VPC endpoints appear in console
- [ ] Security groups allow HTTPS 443 from private subnets
- [ ] IAM role attached to EC2 instance profile

### Phase 2: EC2 Connectivity
- [ ] EC2 boots successfully (check in console)
- [ ] EC2 runs SSM agent (check Systems Manager > Fleet Manager)
- [ ] No public IP assigned (verify in console)

### Phase 3: AWS API Access (via Endpoints)
- [ ] Session Manager session starts (no SSH errors)
- [ ] From session: `aws ssm get-parameter --name /lab/db/endpoint` works
- [ ] From session: `aws secretsmanager get-secret-value --secret-id lab1a/rds/mysql` works
- [ ] From session: CloudWatch agent can post logs

### Phase 4: Logs & Monitoring
- [ ] Logs appear in CloudWatch `/aws/ec2/bonus-a-rds-app` log group
- [ ] No errors about "connection refused" or "access denied"

---

## Troubleshooting

### Problem: "EC2 instance does not appear in Systems Manager > Fleet Manager"

**Cause**: SSM agent not running or IAM role missing permissions.

**Fix**:
```bash
# On EC2 (via Session Manager if available, or manually):
sudo systemctl status snap.amazon-ssm-agent.amazon-ssm-agent
sudo systemctl start snap.amazon-ssm-agent.amazon-ssm-agent

# Verify IAM role is attached:
aws sts get-caller-identity  # from EC2 instance
```

### Problem: "Failed to start Session Manager session"

**Causes**:
1. VPC endpoints not ready (takes ~2-3 min after apply)
2. Security group not allowing HTTPS 443 from EC2 SG
3. IAM role missing `ssmmessages:*` or `ec2messages:*`

**Fix**:
```bash
# From EC2 (if you can access it):
curl -v https://ssmmessages.us-east-1.amazonaws.com  # should succeed

# Check SG rules:
aws ec2 describe-security-groups --group-ids sg-xxxxx
# Should show egress HTTPS to endpoints SG

# Check IAM role:
aws iam get-role-policy --role-name bonus-a-ec2-xxx --policy-name bonus-a-ssm-session-xxx
```

### Problem: "Instance cannot read secrets"

**Cause**: IAM policy resource ARN mismatch.

**Fix**:
```bash
# Verify secret name matches policy:
aws secretsmanager describe-secret --secret-id lab1a/rds/mysql
# Note the ARN

# Update policy resource to match (should end with *):
# Resource = "arn:aws:secretsmanager:us-east-1:ACCOUNT:secret:lab1a/rds/mysql*"
```

### Problem: "S3 Gateway Endpoint not working"

**Cause**: Route table missing S3 prefix list route.

**Fix**:
```bash
# Check route table:
aws ec2 describe-route-tables --route-table-ids rtb-xxxxx

# Should see:
# Destination: pl-xxxxx (prefix list)
# Target: vpce-xxxxx (S3 endpoint)

# If missing, Terraform should add it automatically:
terraform apply  # re-run to add routes
```

---

## Security Checklist (Interview-Ready)

- ✅ **Private Compute**: No public IP = no internet exposure
- ✅ **Network Segmentation**: Private subnets separate from public
- ✅ **API Gateway**: VPC endpoints replace internet for AWS services
- ✅ **Access Control**: IAM role scoped to specific resources
- ✅ **Audit Trail**: SSM Session Manager logs all shell activity
- ✅ **Encryption**: HTTPS to endpoints, KMS endpoint available
- ✅ **Secrets**: Credentials in Secrets Manager, not hardcoded
- ✅ **Observability**: CloudWatch Logs via private endpoint
- ✅ **No Bastion**: Session Manager eliminates bastion maintenance

**Interview Talking Points**:
> "We deployed private EC2 compute with VPC endpoints to eliminate internet exposure. Session Manager replaces SSH, reducing key management burden. IAM policies are least-privilege—the instance can only read its own secrets and parameters. This mirrors how regulated firms handle PCI-DSS, HIPAA, and SOC2 requirements."

---

## Next Steps (Bonus A+)

1. **Golden AMI**: Pre-bake `lab1a` app into AMI to avoid yum/apt internet needs
2. **Secrets Rotation**: Enable automatic rotation in Secrets Manager
3. **Multi-AZ RDS**: Modify RDS for high availability (outside Bonus A scope)
4. **VPC Flow Logs**: Log all network traffic to S3 for compliance audit
5. **Custom Metrics**: App emits `DBConnectionErrors` metric → SNS alarm

---

## Cost Estimate (1 month, us-east-1)

| Resource | Unit Price | Quantity | Monthly |
|----------|-----------|----------|---------|
| EC2 t3.micro (private) | $0.01/hr | 730 | $7.30 |
| VPC Endpoints (7x) | $7.20/endpoint/month | 7 | $50.40 |
| Data transfer (via endpoint) | $0.02/GB | ~5GB | $0.10 |
| CloudWatch Logs | $0.50/GB ingested | ~2GB | $1.00 |
| **Total** | | | **~$59/month** |

**NAT Gateway cost (for comparison)**: $0.045/hr = $32.85/month + $0.045/GB

> Bonus A is ~$26/month more expensive but provides better security and observability.

---

## References

- [AWS VPC Endpoints Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints.html)
- [SSM Session Manager Best Practices](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [IAM Least Privilege](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html#grant-least-privilege)
- [CIS AWS Foundations Benchmark](https://www.cisecurity.org/benchmark/amazon_web_services)

---

**Document Version**: 1.0  
**Last Updated**: January 21, 2026  
**Author**: TheoWAF Class 7 - Armageddon Lab
