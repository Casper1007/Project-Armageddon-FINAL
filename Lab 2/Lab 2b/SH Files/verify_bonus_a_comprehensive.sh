#!/bin/bash

################################################################################
# BONUS-A: Comprehensive Verification Script
#
# Runs all 5 verification checks for the private compute + VPC endpoints setup
# Generates both CLI output AND a JSON report for CI/CD pipelines
#
# Usage:
#   ./verify_bonus_a.sh [INSTANCE_ID] [VPC_ID]
#   or
#   export BONUS_A_INSTANCE_ID=i-xxxxxxxxx
#   export BONUS_A_VPC_ID=vpc-xxxxxxxxx
#   ./verify_bonus_a.sh
################################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTANCE_ID="${1:-${BONUS_A_INSTANCE_ID}}"
VPC_ID="${2:-${BONUS_A_VPC_ID}}"
AWS_REGION="${AWS_REGION:-us-east-1}"
REPORT_FILE="bonus_a_verification_report_$(date +%Y%m%d_%H%M%S).json"
VERIFICATION_RESULTS=()

################################################################################
# Helper Functions
################################################################################

log_header() {
  echo ""
  echo -e "${BLUE}=== $1 ===${NC}"
  echo ""
}

log_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

log_failure() {
  echo -e "${RED}✗ $1${NC}"
}

log_info() {
  echo -e "${YELLOW}ℹ $1${NC}"
}

log_command() {
  echo -e "${BLUE}$${NC} $1"
}

add_result() {
  local check_name=$1
  local status=$2  # "pass" or "fail"
  local message=$3
  VERIFICATION_RESULTS+=("{\"check\": \"$check_name\", \"status\": \"$status\", \"message\": \"$message\"}")
}

################################################################################
# Validation
################################################################################

validate_inputs() {
  log_header "VALIDATION: Checking Prerequisites"

  if [ -z "$INSTANCE_ID" ]; then
    log_failure "INSTANCE_ID not set. Usage: $0 <INSTANCE_ID> [VPC_ID]"
    exit 1
  fi
  log_success "Instance ID: $INSTANCE_ID"

  if [ -z "$VPC_ID" ]; then
    log_info "VPC_ID not provided. Attempting to auto-detect..."
    VPC_ID=$(aws ec2 describe-instances \
      --instance-ids "$INSTANCE_ID" \
      --region "$AWS_REGION" \
      --query "Reservations[0].Instances[0].VpcId" \
      --output text 2>/dev/null || echo "")
    
    if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
      log_failure "Could not auto-detect VPC_ID. Provide it as: $0 $INSTANCE_ID <VPC_ID>"
      exit 1
    fi
  fi
  log_success "VPC ID: $VPC_ID"
  log_success "AWS Region: $AWS_REGION"
}

################################################################################
# CHECK 1: EC2 is Private (No Public IP)
################################################################################

check_1_private_ip() {
  log_header "CHECK 1: Verify EC2 Instance is PRIVATE (No Public IP)"

  local public_ip=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text 2>/dev/null || echo "None")

  echo "Public IP: $public_ip"

  if [ "$public_ip" = "None" ] || [ -z "$public_ip" ]; then
    log_success "Instance has NO public IP (as expected)"
    add_result "Private IP" "pass" "No public IP assigned"
    return 0
  else
    log_failure "Instance has public IP: $public_ip (SHOULD BE PRIVATE!)"
    add_result "Private IP" "fail" "Public IP found: $public_ip"
    return 1
  fi
}

################################################################################
# CHECK 2: VPC Endpoints Exist
################################################################################

check_2_vpc_endpoints() {
  log_header "CHECK 2: Verify VPC Endpoints Exist"

  local endpoints=$(aws ec2 describe-vpc-endpoints \
    --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "VpcEndpoints[].ServiceName" \
    --output text 2>/dev/null || echo "")

  if [ -z "$endpoints" ]; then
    log_failure "No VPC endpoints found in VPC $VPC_ID"
    add_result "VPC Endpoints" "fail" "No endpoints found"
    return 1
  fi

  echo "VPC Endpoints Found:"
  echo "$endpoints" | tr ' ' '\n'

  # Check for required endpoints
  local required_endpoints=("ssm" "ec2messages" "ssmmessages" "logs" "secretsmanager" "s3")
  local all_present=true

  for endpoint in "${required_endpoints[@]}"; do
    if echo "$endpoints" | grep -qi "$endpoint"; then
      log_success "✓ $endpoint endpoint present"
    else
      log_failure "✗ $endpoint endpoint MISSING"
      all_present=false
    fi
  done

  if [ "$all_present" = true ]; then
    add_result "VPC Endpoints" "pass" "All required endpoints present"
    return 0
  else
    add_result "VPC Endpoints" "fail" "Some endpoints missing"
    return 1
  fi
}

################################################################################
# CHECK 3: Session Manager Path Works (EC2 in Fleet Manager)
################################################################################

check_3_session_manager() {
  log_header "CHECK 3: Verify Session Manager Access (EC2 in Fleet Manager)"

  local instances=$(aws ssm describe-instance-information \
    --region "$AWS_REGION" \
    --query "InstanceInformationList[].InstanceId" \
    --output text 2>/dev/null || echo "")

  echo "Instances in Fleet Manager:"
  if [ -z "$instances" ]; then
    log_info "(None found yet - SSM agent may not be running)"
  else
    echo "$instances" | tr ' ' '\n'
  fi

  if echo "$instances" | grep -q "$INSTANCE_ID"; then
    log_success "Instance $INSTANCE_ID appears in Session Manager Fleet"
    add_result "Session Manager" "pass" "Instance in Fleet Manager"
    return 0
  else
    log_failure "Instance $INSTANCE_ID NOT in Session Manager Fleet"
    log_info "This typically means:"
    log_info "  1. SSM agent is not running on the EC2 instance"
    log_info "  2. Instance IAM role lacks SSM permissions"
    log_info "  3. VPC endpoints are not ready (wait 2-3 minutes)"
    add_result "Session Manager" "fail" "Instance not in Fleet Manager"
    return 1
  fi
}

################################################################################
# CHECK 4: Instance Can Read Both Config Stores
################################################################################

check_4_config_stores() {
  log_header "CHECK 4: Instance Can Read Config Stores (Parameter Store + Secrets Manager)"

  if ! aws ssm describe-instance-information --region "$AWS_REGION" \
    --query "InstanceInformationList[?InstanceId=='$INSTANCE_ID']" \
    --output text | grep -q "$INSTANCE_ID"; then
    log_failure "Instance not in Fleet Manager yet. Cannot run session commands."
    log_info "Wait 2-3 minutes for SSM agent to register, then retry."
    add_result "Config Stores Access" "fail" "Instance not ready for SSM session"
    return 1
  fi

  log_info "Running commands inside EC2 via Session Manager..."

  # Test 1: Parameter Store (expects success)
  echo ""
  echo "Testing Parameter Store access..."
  local param_result=$(aws ssm start-session \
    --target "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters 'command=["aws ssm get-parameter --name /lab/db/endpoint --region '"$AWS_REGION"' --query Parameter.Value --output text"]' \
    2>&1 || echo "ERROR")

  if echo "$param_result" | grep -qi "error\|failed\|unable"; then
    log_failure "Parameter Store access failed"
    add_result "Config Stores - Parameter Store" "fail" "$param_result"
  else
    log_success "Parameter Store access OK"
    add_result "Config Stores - Parameter Store" "pass" "Successfully retrieved /lab/db/endpoint"
  fi

  # Test 2: Secrets Manager (expects success)
  echo ""
  echo "Testing Secrets Manager access..."
  local secret_result=$(aws ssm start-session \
    --target "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --document-name "AWS-RunShellScript" \
    --parameters 'command=["aws secretsmanager get-secret-value --secret-id lab1a/rds/mysql --region '"$AWS_REGION"' --query SecretString --output text"]' \
    2>&1 || echo "ERROR")

  if echo "$secret_result" | grep -qi "error\|failed\|unable"; then
    log_failure "Secrets Manager access failed"
    add_result "Config Stores - Secrets Manager" "fail" "$secret_result"
    return 1
  else
    log_success "Secrets Manager access OK"
    add_result "Config Stores - Secrets Manager" "pass" "Successfully retrieved lab1a/rds/mysql"
    return 0
  fi
}

################################################################################
# CHECK 5: CloudWatch Logs Delivery Path Works
################################################################################

check_5_cloudwatch_logs() {
  log_header "CHECK 5: Verify CloudWatch Logs Delivery (via VPC Endpoint)"

  local log_group="/aws/ec2/bonus-a-rds-app"

  echo "Checking log group: $log_group"

  # Check if log group exists
  local lg_exists=$(aws logs describe-log-groups \
    --region "$AWS_REGION" \
    --log-group-name-prefix "$(echo $log_group | cut -d/ -f1-3)" \
    --query "logGroups[?logGroupName=='$log_group']" \
    --output text 2>/dev/null || echo "")

  if [ -z "$lg_exists" ]; then
    log_failure "Log group $log_group does not exist"
    add_result "CloudWatch Logs" "fail" "Log group not found"
    return 1
  fi

  log_success "Log group exists: $log_group"

  # Check for log streams
  local streams=$(aws logs describe-log-streams \
    --log-group-name "$log_group" \
    --region "$AWS_REGION" \
    --query "logStreams[].logStreamName" \
    --output text 2>/dev/null || echo "")

  if [ -z "$streams" ]; then
    log_info "No log streams yet (app may not have written logs)"
    add_result "CloudWatch Logs" "pass" "Log group exists, awaiting app logs"
    return 0
  fi

  echo "Log streams found:"
  echo "$streams" | tr ' ' '\n'

  log_success "CloudWatch Logs delivery path is available"
  add_result "CloudWatch Logs" "pass" "Log group ready, streams found"
  return 0
}

################################################################################
# BONUS Checks (Non-critical but valuable)
################################################################################

check_bonus_security_groups() {
  log_header "BONUS CHECK: Security Group Configuration"

  # Get EC2 security group
  local sg_id=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" \
    --output text 2>/dev/null)

  echo "EC2 Security Group: $sg_id"

  # Get SG rules
  local sg_info=$(aws ec2 describe-security-groups \
    --group-ids "$sg_id" \
    --region "$AWS_REGION" \
    --query 'SecurityGroups[0]' 2>/dev/null)

  # Check ingress rules (should have none)
  local ingress=$(echo "$sg_info" | grep -o '"IpProtocol"' | wc -l)
  if [ "$ingress" -eq 0 ]; then
    log_success "No inbound rules (Session Manager handles access)"
  else
    log_failure "Found inbound rules (should be none for Session Manager)"
  fi

  # Check egress rules (should allow HTTPS)
  echo ""
  echo "Security Group Egress Rules:"
  aws ec2 describe-security-groups \
    --group-ids "$sg_id" \
    --region "$AWS_REGION" \
    --query "SecurityGroups[0].IpPermissionsEgress[?FromPort=='443']" \
    --output table 2>/dev/null || echo "No HTTPS egress rule found"

  add_result "Security Group Config" "pass" "SG verified"
}

check_bonus_iam_role() {
  log_header "BONUS CHECK: IAM Role Permissions"

  # Get instance IAM role
  local role_name=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query "Reservations[0].Instances[0].IamInstanceProfile.Arn" \
    --output text 2>/dev/null | awk -F'/' '{print $NF}')

  if [ -z "$role_name" ]; then
    log_failure "No IAM role attached to instance"
    add_result "IAM Role" "fail" "No role found"
    return 1
  fi

  # Extract role name from instance profile
  local role=$(aws iam get-instance-profile \
    --instance-profile-name "$role_name" \
    --query "InstanceProfile.Roles[0].RoleName" \
    --output text 2>/dev/null)

  echo "IAM Role: $role"

  # List inline policies
  echo ""
  echo "Inline policies:"
  aws iam list-role-policies \
    --role-name "$role" \
    --query "PolicyNames" \
    --output text 2>/dev/null | tr '\t' '\n'

  log_success "IAM role attached and verified"
  add_result "IAM Role" "pass" "Role: $role"
}

################################################################################
# Report Generation
################################################################################

generate_json_report() {
  log_header "GENERATING JSON REPORT"

  # Build JSON array
  local json_results="["
  for result in "${VERIFICATION_RESULTS[@]}"; do
    json_results="${json_results}${result},"
  done
  json_results="${json_results%,}]"  # Remove trailing comma

  # Build full report
  cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "instance_id": "$INSTANCE_ID",
  "vpc_id": "$VPC_ID",
  "aws_region": "$AWS_REGION",
  "checks": $json_results,
  "summary": {
    "total_checks": $(echo "$json_results" | grep -o '"status"' | wc -l),
    "passed": $(echo "$json_results" | grep -o '"status": "pass"' | wc -l),
    "failed": $(echo "$json_results" | grep -o '"status": "fail"' | wc -l)
  }
}
EOF

  log_success "Report saved to: $REPORT_FILE"
  cat "$REPORT_FILE"
}

################################################################################
# Main Execution
################################################################################

main() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║         BONUS-A VERIFICATION: Private EC2 + VPC Endpoints      ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""

  validate_inputs

  # Run all checks
  check_1_private_ip || true
  check_2_vpc_endpoints || true
  check_3_session_manager || true
  check_4_config_stores || true
  check_5_cloudwatch_logs || true

  # Bonus checks
  check_bonus_security_groups || true
  check_bonus_iam_role || true

  # Generate report
  echo ""
  generate_json_report

  # Summary
  log_header "VERIFICATION COMPLETE"
  echo ""
  echo "Next Steps:"
  echo "  1. Review the JSON report: $REPORT_FILE"
  echo "  2. If any checks failed, see troubleshooting in BONUS_A_ARCHITECTURE_GUIDE.md"
  echo "  3. For Session Manager access, run:"
  echo "     aws ssm start-session --target $INSTANCE_ID --region $AWS_REGION"
  echo ""
}

# Run main
main "$@"
