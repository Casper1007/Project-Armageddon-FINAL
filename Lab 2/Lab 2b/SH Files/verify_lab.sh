#!/bin/bash
#
# EC2 → RDS Integration Lab - Verification Script
# This script validates that your infrastructure is correctly configured
# Run with: bash verify_lab.sh
#

set -euo pipefail

REGION="us-east-1"
PROJECT_NAME="chrisbarm"
DB_NAME="chrisbarm-rds01"
EC2_TAG_NAME="chrisbarm-ec2_01"
EC2_SG_NAME="${PROJECT_NAME}-ec2-sg01"
RDS_SG_NAME="${PROJECT_NAME}-rds-sg01"
SECRET_NAME="lab1a/rds/mysql"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0
WARN=0

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ $1${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}\n"
}

print_test() {
    echo -e "${YELLOW}→${NC} Testing: $1"
}

print_pass() {
    echo -e "${GREEN}✓${NC} PASS: $1"
    ((PASS++))
}

print_fail() {
    echo -e "${RED}✗${NC} FAIL: $1"
    ((FAIL++))
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} WARN: $1"
    ((WARN++))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} INFO: $1"
}

# ============================================================================
# Section 1: EC2 Verification
# ============================================================================

print_header "Section 1: EC2 Instance Verification"

print_test "EC2 instance exists and is running"
EC2_INSTANCE=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${EC2_TAG_NAME}" \
    --region "${REGION}" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text 2>/dev/null || echo "")

if [ -n "$EC2_INSTANCE" ] && [ "$EC2_INSTANCE" != "None" ]; then
    EC2_STATE=$(aws ec2 describe-instances \
        --instance-ids "$EC2_INSTANCE" \
        --region "${REGION}" \
        --query "Reservations[0].Instances[0].State.Name" \
        --output text)
    
    if [ "$EC2_STATE" = "running" ]; then
        print_pass "EC2 instance $EC2_INSTANCE is running"
        EC2_PUBLIC_IP=$(aws ec2 describe-instances \
            --instance-ids "$EC2_INSTANCE" \
            --region "${REGION}" \
            --query "Reservations[0].Instances[0].PublicIpAddress" \
            --output text)
        print_info "EC2 Public IP: $EC2_PUBLIC_IP"
    else
        print_fail "EC2 instance is in state: $EC2_STATE (expected: running)"
    fi
else
    print_fail "EC2 instance not found with tag Name=$EC2_TAG_NAME"
    EC2_INSTANCE=""
fi

# ============================================================================
# Section 2: IAM Role Verification
# ============================================================================

print_header "Section 2: IAM Role & Instance Profile Verification"

if [ -n "$EC2_INSTANCE" ]; then
    print_test "IAM instance profile attached to EC2"
    IAM_PROFILE=$(aws ec2 describe-instances \
        --instance-ids "$EC2_INSTANCE" \
        --region "${REGION}" \
        --query "Reservations[0].Instances[0].IamInstanceProfile.Arn" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$IAM_PROFILE" ] && [ "$IAM_PROFILE" != "None" ]; then
        print_pass "IAM instance profile attached: $IAM_PROFILE"
        
        # Extract role name
        ROLE_NAME=$(echo "$IAM_PROFILE" | grep -oP '(?<=instance-profile/)[^/]+')
        print_info "Instance profile name: $ROLE_NAME"
        
        # Verify policies attached
        print_test "Required policies attached to role"
        ROLE_ARN=$(aws iam get-instance-profile \
            --instance-profile-name "$ROLE_NAME" \
            --query "InstanceProfile.Roles[0].Arn" \
            --output text)
        
        ROLE_NAME_FULL=$(aws iam get-instance-profile \
            --instance-profile-name "$ROLE_NAME" \
            --query "InstanceProfile.Roles[0].RoleName" \
            --output text)
        
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$ROLE_NAME_FULL" \
            --query "AttachedPolicies[].PolicyName" \
            --output text)
        
        if echo "$ATTACHED_POLICIES" | grep -q "AmazonSSMManagedInstanceCore"; then
            print_pass "SSM policy (AmazonSSMManagedInstanceCore) attached"
        else
            print_warn "SSM policy not found - EC2 Instance Connect may not work"
        fi
        
        if echo "$ATTACHED_POLICIES" | grep -q "CloudWatchAgentServerPolicy"; then
            print_pass "CloudWatch policy attached"
        else
            print_warn "CloudWatch policy not attached"
        fi
        
    else
        print_fail "No IAM instance profile attached to EC2"
    fi
else
    print_warn "Skipping IAM verification - EC2 instance not found"
fi

# ============================================================================
# Section 3: RDS Verification
# ============================================================================

print_header "Section 3: RDS Instance Verification"

print_test "RDS instance exists and is available"
RDS_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_NAME" \
    --region "${REGION}" \
    --query "DBInstances[0].DBInstanceStatus" \
    --output text 2>/dev/null || echo "")

if [ "$RDS_STATUS" = "available" ]; then
    print_pass "RDS instance $DB_NAME is available"
    
    RDS_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_NAME" \
        --region "${REGION}" \
        --query "DBInstances[0].Endpoint.Address" \
        --output text)
    
    RDS_PORT=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_NAME" \
        --region "${REGION}" \
        --query "DBInstances[0].Endpoint.Port" \
        --output text)
    
    print_info "RDS Endpoint: $RDS_ENDPOINT:$RDS_PORT"
    
    # Verify not publicly accessible
    IS_PUBLIC=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_NAME" \
        --region "${REGION}" \
        --query "DBInstances[0].PubliclyAccessible" \
        --output text)
    
    if [ "$IS_PUBLIC" = "False" ]; then
        print_pass "RDS instance is NOT publicly accessible (correct)"
    else
        print_warn "RDS instance is publicly accessible (security risk!)"
    fi
    
    # Check encryption
    IS_ENCRYPTED=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_NAME" \
        --region "${REGION}" \
        --query "DBInstances[0].StorageEncrypted" \
        --output text)
    
    if [ "$IS_ENCRYPTED" = "True" ]; then
        print_pass "RDS storage is encrypted"
    else
        print_info "RDS storage encryption: $IS_ENCRYPTED"
    fi
    
else
    print_fail "RDS instance status: $RDS_STATUS (expected: available)"
fi

# ============================================================================
# Section 4: Security Group Verification
# ============================================================================

print_header "Section 4: Security Group Configuration"

print_test "RDS security group has correct inbound rule"
RDS_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${RDS_SG_NAME}" \
    --region "${REGION}" \
    --query "SecurityGroups[0].GroupId" \
    --output text 2>/dev/null || echo "")

if [ -n "$RDS_SG_ID" ] && [ "$RDS_SG_ID" != "None" ]; then
    print_info "RDS Security Group ID: $RDS_SG_ID"
    
    # Get EC2 SG ID
    EC2_SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${EC2_SG_NAME}" \
        --region "${REGION}" \
        --query "SecurityGroups[0].GroupId" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$EC2_SG_ID" ] && [ "$EC2_SG_ID" != "None" ]; then
        print_info "EC2 Security Group ID: $EC2_SG_ID"
        
        # Check for MySQL rule
        MYSQL_RULE=$(aws ec2 describe-security-group-rules \
            --filters "Name=group-id,Values=${RDS_SG_ID}" \
                      "Name=from-port,Values=3306" \
                      "Name=to-port,Values=3306" \
                      "Name=ip-protocol,Values=tcp" \
            --region "${REGION}" \
            --query "SecurityGroupRules[?ReferencedGroupInfo.GroupId=='${EC2_SG_ID}']" \
            --output json 2>/dev/null || echo "[]")
        
        if echo "$MYSQL_RULE" | grep -q "ReferencedGroupInfo"; then
            print_pass "RDS SG allows MySQL (port 3306) from EC2 SG"
        else
            print_fail "RDS SG does NOT allow MySQL from EC2 SG (CIDR rule detected - INSECURE)"
        fi
    else
        print_fail "EC2 security group not found"
    fi
else
    print_fail "RDS security group not found"
fi

# ============================================================================
# Section 5: Secrets Manager Verification
# ============================================================================

print_header "Section 5: Secrets Manager Configuration"

print_test "Database credentials stored in Secrets Manager"
SECRET_ARN=$(aws secretsmanager describe-secret \
    --secret-id "$SECRET_NAME" \
    --region "${REGION}" \
    --query "ARN" \
    --output text 2>/dev/null || echo "")

if [ -n "$SECRET_ARN" ] && [ "$SECRET_ARN" != "None" ]; then
    print_pass "Secret found: $SECRET_NAME"
    print_info "Secret ARN: $SECRET_ARN"
    
    # Show secret structure (without password)
    SECRET_VALUE=$(aws secretsmanager get-secret-value \
        --secret-id "$SECRET_NAME" \
        --region "${REGION}" \
        --query "SecretString" \
        --output text 2>/dev/null || echo "")
    
    if echo "$SECRET_VALUE" | grep -q "username"; then
        print_pass "Secret contains database credentials"
        DB_USERNAME=$(echo "$SECRET_VALUE" | grep -oP '(?<="username":")\w+(?=")')
        DB_HOST=$(echo "$SECRET_VALUE" | grep -oP '(?<="host":")[^"]+(?=")')
        print_info "DB Username: $DB_USERNAME"
        print_info "DB Host: $DB_HOST"
    else
        print_fail "Secret format invalid or empty"
    fi
else
    print_fail "Secret not found: $SECRET_NAME"
fi

# ============================================================================
# Section 6: IAM Policy Verification
# ============================================================================

print_header "Section 6: IAM Policy for Secrets Manager Access"

if [ -n "$EC2_INSTANCE" ] && [ -n "$ROLE_NAME_FULL" ]; then
    print_test "EC2 role can access Secrets Manager secret"
    
    # Get inline policies
    INLINE_POLICIES=$(aws iam list-role-policies \
        --role-name "$ROLE_NAME_FULL" \
        --query "PolicyNames" \
        --output text 2>/dev/null || echo "")
    
    if echo "$INLINE_POLICIES" | grep -q "secrets_policy"; then
        print_pass "Custom secrets policy attached"
        
        # Get policy document
        POLICY_DOC=$(aws iam get-role-policy \
            --role-name "$ROLE_NAME_FULL" \
            --policy-name "secrets_policy" \
            --query "RolePolicyDocument" \
            --output json)
        
        if echo "$POLICY_DOC" | grep -q "secretsmanager:GetSecretValue"; then
            print_pass "Policy includes secretsmanager:GetSecretValue permission"
        else
            print_warn "Policy does not explicitly grant GetSecretValue"
        fi
    else
        print_warn "Custom secrets policy not found in inline policies"
    fi
else
    print_warn "Skipping policy check - role information not available"
fi

# ============================================================================
# Section 7: Application Health Check
# ============================================================================

print_header "Section 7: Application Health & Connectivity"

if [ -n "$EC2_PUBLIC_IP" ]; then
    print_test "Flask application is accessible"
    
    # Try to reach the app
    HTTP_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/response.json \
        "http://${EC2_PUBLIC_IP}/" \
        --max-time 10 2>/dev/null || echo "000")
    
    if [ "$HTTP_RESPONSE" = "200" ]; then
        print_pass "Application is responding (HTTP 200)"
        
        # Check if we can parse the JSON
        if jq . /tmp/response.json > /dev/null 2>&1; then
            SERVICE=$(jq -r '.service' /tmp/response.json)
            STATUS=$(jq -r '.status' /tmp/response.json)
            print_info "Service: $SERVICE"
            print_info "Status: $STATUS"
        fi
    else
        print_warn "Application not responding (HTTP $HTTP_RESPONSE)"
        print_info "This is expected if user-data script is still executing"
        print_info "Wait 2-5 minutes after EC2 launch before testing"
    fi
    
    # Check health endpoint
    print_test "Database connectivity health check"
    HEALTH_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/health.json \
        "http://${EC2_PUBLIC_IP}/health" \
        --max-time 10 2>/dev/null || echo "000")
    
    if [ "$HEALTH_RESPONSE" = "200" ] || [ "$HEALTH_RESPONSE" = "503" ]; then
        if jq . /tmp/health.json > /dev/null 2>&1; then
            HEALTH_STATUS=$(jq -r '.status' /tmp/health.json)
            print_info "Health check status: $HEALTH_STATUS"
        fi
    fi
    
    print_info "Test endpoints:"
    print_info "  - Initialize DB:  curl -X POST http://${EC2_PUBLIC_IP}/init"
    print_info "  - Add note:        curl 'http://${EC2_PUBLIC_IP}/add?note=test_note'"
    print_info "  - List notes:      curl http://${EC2_PUBLIC_IP}/list"
    
else
    print_warn "EC2 public IP not available - cannot test connectivity"
fi

# ============================================================================
# Summary
# ============================================================================

print_header "Verification Summary"

echo -e "${GREEN}Passed:  $PASS${NC}"
echo -e "${YELLOW}Warnings: $WARN${NC}"
echo -e "${RED}Failed:  $FAIL${NC}"

if [ $FAIL -eq 0 ]; then
    echo -e "\n${GREEN}✓ All critical checks passed!${NC}"
    if [ $WARN -gt 0 ]; then
        echo -e "${YELLOW}⚠ Review warnings above for optimization opportunities${NC}"
    fi
    exit 0
else
    echo -e "\n${RED}✗ Some checks failed. Please review above.${NC}"
    exit 1
fi
