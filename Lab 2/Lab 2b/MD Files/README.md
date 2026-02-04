# EC2 → RDS Integration Lab - Implementation Complete

## 📋 Overview

This lab demonstrates a **production-ready cloud architecture pattern** used in enterprise AWS applications:

```
[User/Browser] 
       ↓ HTTP
    [EC2 Instance with Flask App]
       ↓ (IAM Role)
    [Secrets Manager] → Retrieves DB Credentials
       ↓ (Private Subnet)
    [RDS MySQL Database]
```

**Key Principle**: Secure, credential-less EC2-to-RDS communication using AWS native security services.

---

## ✅ What Has Been Deployed

### Infrastructure (Terraform)
- ✅ VPC with public/private subnets across 2 AZs
- ✅ EC2 instance in public subnet with IAM role
- ✅ RDS MySQL instance in private subnet
- ✅ Security groups with least-privilege rules
- ✅ IAM role with Secrets Manager access
- ✅ Secrets Manager storing database credentials
- ✅ NAT Gateway for private subnet internet access
- ✅ CloudWatch monitoring and SNS alerts

### Application (Flask + Python)
- ✅ Python Flask web framework
- ✅ MySQL connector driver
- ✅ Automatic Secrets Manager credential retrieval
- ✅ Database schema initialization
- ✅ RESTful endpoints: `/init`, `/add`, `/list`
- ✅ Comprehensive error handling and logging
- ✅ Health check endpoint

### Automation
- ✅ User data script (EC2 startup automation)
- ✅ Automated package installation
- ✅ Automatic application deployment
- ✅ Background process management

---

## 🔍 How to Verify Everything Works

### Step 1: Check EC2 Instance Status

```bash
# Verify EC2 is running
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=chrisbarm-ec2_01" \
  --region us-east-1 \
  --query "Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]" \
  --output table
```

**Expected**: Instance should show state = `running`  
**Get from output**: The public IP (e.g., 54.91.122.42)

### Step 2: Check RDS Status

```bash
# Verify RDS is available
aws rds describe-db-instances \
  --db-instance-identifier chrisbarm-rds01 \
  --region us-east-1 \
  --query "DBInstances[0].[DBInstanceStatus,Endpoint.Address,PubliclyAccessible]" \
  --output table
```

**Expected**:
- Status: `available`
- Endpoint: `chrisbarm-rds01.c4x68420cyvy.us-east-1.rds.amazonaws.com`
- Publicly Accessible: `False` ✅ (security best practice)

### Step 3: Verify Security Groups

```bash
# Check RDS security group allows MySQL from EC2
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$(aws ec2 describe-security-groups --filters Name=group-name,Values=chrisbarm-rds-sg01 --region us-east-1 --query SecurityGroups[0].GroupId --output text)" \
  --region us-east-1 \
  --output table
```

**Expected**: Should show TCP port 3306 with reference to EC2 security group (NOT 0.0.0.0/0)

### Step 4: Verify IAM Role

```bash
# Check EC2 has IAM role attached
aws ec2 describe-instances \
  --instance-ids i-061b663d2d9d6ff80 \
  --region us-east-1 \
  --query "Reservations[].Instances[].IamInstanceProfile.Arn" \
  --output text
```

**Expected**: Should show ARN like `arn:aws:iam::198547498722:instance-profile/chrisbarm-instance-profile01`

### Step 5: Verify Secrets Manager

```bash
# Check secret exists and is accessible
aws secretsmanager get-secret-value \
  --secret-id lab1a/rds/mysql \
  --region us-east-1 \
  --query 'SecretString' \
  --output text | jq .
```

**Expected**: JSON with username, password, host, port, dbname

### Step 6: Test Application (After Startup Complete)

⏳ **IMPORTANT**: Wait **2-5 minutes** after EC2 instance creation for startup script to complete

```bash
# Test health endpoint
curl http://54.91.122.42/

# Expected response:
# {
#   "service": "EC2 → RDS Integration Lab",
#   "status": "running",
#   "endpoints": {...}
# }
```

---

## 🚀 Testing the Complete Data Flow

Once the application is running:

### A. Initialize Database

```bash
# Create tables in RDS
curl -X POST http://54.91.122.42/init

# Expected:
# {"status":"success","message":"Database initialized"}
```

### B. Insert Data

```bash
# Add a note
curl "http://54.91.122.42/add?note=cloud_labs_are_real"

# Expected:
# {"status":"success","message":"Note added"}
```

### C. Retrieve Data

```bash
# List all notes from RDS
curl http://54.91.122.42/list

# Expected:
# {
#   "status": "success",
#   "notes": [
#     {
#       "id": 1,
#       "note": "cloud_labs_are_real",
#       "created_at": "2026-01-20 10:15:42"
#     }
#   ]
# }
```

### D. Verify Persistence

```bash
# Call /list again - data should persist
curl http://54.91.122.42/list

# Same data should be returned even if app restarts
```

---

## 🔐 Security Model Explanation

### What This Architecture Prevents

| Attack Vector | How It's Blocked |
|---|---|
| **Credential Exposure** | Secrets Manager = No hardcoded passwords |
| **Lateral Movement** | Security groups = RDS isolated to EC2 only |
| **Internet Attack** | RDS not publicly accessible (private subnet) |
| **Privilege Escalation** | IAM roles = Least privilege by design |
| **Credential Rotation** | Centralized management via Secrets Manager |
| **Audit Trail Loss** | All API calls logged to CloudTrail |

### Security Groups (The Primary Firewall)

```
Internet (0.0.0.0/0)
         ↓
    [EC2 SG]
    - Inbound: HTTP 80 from anywhere ✅
    - Outbound: All traffic ✅
         ↓
    [RDS SG]
    - Inbound: MySQL 3306 ONLY from EC2 SG ✅✅✅ (CRITICAL)
    - Outbound: None needed (RDS doesn't initiate)
         ↓
    Private Subnet (Hidden from Internet)
```

This is the **primary AWS network security boundary**.

---

## 📁 File Structure

```
terraform_restart_fixed/
├── main.tf                          # All resource definitions
├── providers.tf                     # AWS provider config
├── variables.tf                     # Variable definitions
├── outputs.tf                       # Output values
├── versions.tf                      # Terraform version constraints
├── 1a_user_data.sh                  # EC2 startup script
├── app.py                           # Flask application source
├── LAB_VERIFICATION_GUIDE.md        # Detailed verification steps
├── verify_lab.sh                    # Automated verification script
├── test_app.sh                      # Application testing script
├── terraform.tfstate                # Current infrastructure state
└── terraform.tfstate.backup         # State backup
```

---

## 📊 Resource Details

### Compute
- **Instance**: `i-061b663d2d9d6ff80`
- **Type**: `t3.micro` (free tier eligible)
- **AMI**: Ubuntu 22.04 LTS (`ami-0030e4319cbf4dbf2`)
- **Public IP**: `54.91.122.42`
- **Region**: `us-east-1`

### Database
- **Identifier**: `chrisbarm-rds01`
- **Engine**: MySQL 8.0
- **Type**: `db.t3.micro` (free tier eligible)
- **Storage**: 20 GB gp3
- **Endpoint**: `chrisbarm-rds01.c4x68420cyvy.us-east-1.rds.amazonaws.com`
- **Port**: 3306
- **Database**: `labdb`
- **Master User**: `admin` (in Secrets Manager)

### Network
- **VPC**: `vpc-02c6c4d52c0974923` (10.0.0.0/16)
- **Public Subnets**: 10.0.1.0/24, 10.0.2.0/24
- **Private Subnets**: 10.0.101.0/24, 10.0.102.0/24
- **AZs**: us-east-1a, us-east-1b

### Security
- **EC2 SG**: `sg-0fa563fc7b978c1ce` (chrisbarm-ec2-sg01)
- **RDS SG**: `sg-07b6f3b0c45df9bd2` (chrisbarm-rds-sg01)
- **IAM Role**: `chrisbarm-ec2-role01`
- **Instance Profile**: `chrisbarm-instance-profile01`
- **Secret**: `lab1a/rds/mysql` (Secrets Manager)

---

## 🛠️ Troubleshooting

### Application Not Responding

**Symptom**: Connection refused or timeout

**Solution**:
1. Wait 2-5 minutes from EC2 creation
2. Check EC2 logs: SSH to instance and run `tail -f /var/log/rds-app.log`
3. Verify RDS is available: See Step 2 above
4. Verify security groups: See Step 3 above

### Connection Refused from Application

**Symptom**: Application starts but cannot connect to RDS

**Root Cause**: Almost always security groups

**Check**:
```bash
# Verify RDS SG allows EC2 SG
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=sg-07b6f3b0c45df9bd2" \
  --region us-east-1
```

Look for rule with:
- `FromPort: 3306`
- `ToPort: 3306`
- `ReferencedGroupId: sg-0fa563fc7b978c1ce` ← EC2 SG

If not present, security group is misconfigured.

### Secrets Manager Access Denied

**Symptom**: Application logs show "AccessDenied" for Secrets Manager

**Root Cause**: IAM role missing policy

**Check**:
```bash
aws iam get-role-policy \
  --role-name chrisbarm-ec2-role01 \
  --policy-name secrets_policy
```

Should return policy allowing `secretsmanager:GetSecretValue` on the secret ARN.

---

## 📚 What You've Learned

By completing this lab, you now understand:

1. ✅ **Network Security**: Security groups as primary AWS firewall
2. ✅ **IAM Role-Based Access**: No API keys needed on EC2
3. ✅ **Secrets Management**: Centralized credential storage
4. ✅ **Managed Databases**: RDS eliminates operational overhead
5. ✅ **Application Architecture**: Stateless compute + stateful database
6. ✅ **Debugging Cloud Infrastructure**: Using AWS CLI systematically
7. ✅ **Production Patterns**: This exact pattern is in real production systems

---

## 🎯 Why This Matters

This architecture is used in:
- **Internal Tools** (Jira, Confluence run on this)
- **SaaS Products** (API backends typically use this pattern)
- **Microservices** (Database per service, multiple instances)
- **Legacy Modernization** (Lift-and-shift workloads)
- **Cloud Security Assessment** (This pattern proves hardening knowledge)

If you understand this, you understand the **foundation** of real AWS workloads.

---

## 📋 Proof of Completion

To prove this lab is complete, provide:

1. **CLI Output**: Run verification steps 1-5 above and save output
2. **Application Test**: Screenshots or curl responses from `/init`, `/add`, `/list`
3. **Security Group Proof**: Show RDS rule with referenced EC2 SG ID

---

## 🔗 References

- [AWS Security Groups Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html)
- [AWS Secrets Manager Best Practices](https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html)
- [IAM Roles for EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html)
- [RDS Security](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Security.html)
- [Flask Documentation](https://flask.palletsprojects.com/)
- [MySQL Connector Python](https://dev.mysql.com/doc/connector-python/en/)

---

## 📞 Support

If you encounter issues:

1. Check `/var/log/rds-app.log` on EC2
2. Verify all CLI commands in verification section
3. Ensure RDS and EC2 are in same region (us-east-1)
4. Check IAM permissions on your account
5. Review security group rules match expected values

---

**Lab Status**: ✅ **DEPLOYED AND READY FOR TESTING**

**Next Steps**:
1. Wait 2-5 minutes for EC2 startup script to complete
2. Run verification steps above
3. Test application endpoints
4. Verify data persists in RDS
5. Submit proof of completion

Good luck! 🚀
