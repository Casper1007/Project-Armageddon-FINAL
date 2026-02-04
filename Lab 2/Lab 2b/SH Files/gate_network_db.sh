#!/bin/bash
###############################################################################
# gate_network_db.sh
# Verifies RDS networking: not public, SG-to-SG rule, private subnets
# Exit codes: 0=pass, 2=fail, 1=error
###############################################################################

set -euo pipefail

REGION="${REGION:-us-east-1}"
INSTANCE_ID="${INSTANCE_ID:-}"
DB_ID="${DB_ID:-}"
DB_PORT="${DB_PORT:-}"
CHECK_PRIVATE_SUBNETS="${CHECK_PRIVATE_SUBNETS:-false}"

OUTPUT_FILE="gate_network_db.json"

# Initialize result JSON
cat > "$OUTPUT_FILE" << EOF
{
  "test": "gate_network_db",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "passed": true,
  "errors": [],
  "checks": {}
}
EOF

log_error() {
  echo "[ERROR] $1" >&2
  jq ".errors += [\"$1\"]" "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
}

log_check() {
  local check_name="$1"
  local status="$2"
  local details="${3:-}"
  jq ".checks[\"$check_name\"] = {\"status\": \"$status\", \"details\": \"$details\"}" "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
  if [ "$status" != "pass" ]; then
    jq ".passed = false" "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
  fi
}

# Validate inputs
if [ -z "$INSTANCE_ID" ]; then
  log_error "INSTANCE_ID not provided"
  exit 1
fi

if [ -z "$DB_ID" ]; then
  log_error "DB_ID not provided"
  exit 1
fi

# Check 1: RDS instance exists
echo "[*] Checking RDS instance exists..."
DB_INFO=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --region "$REGION" \
  --query 'DBInstances[0]' \
  --output json 2>/dev/null || echo "{}")

if [ "$DB_INFO" = "{}" ]; then
  log_error "RDS instance $DB_ID not found"
  exit 2
fi

log_check "rds_instance_exists" "pass" "DB ID: $DB_ID"
echo "✓ RDS instance exists"

# Check 2: RDS is NOT publicly accessible
echo "[*] Checking RDS is not publicly accessible..."
PUBLICLY_ACCESSIBLE=$(echo "$DB_INFO" | jq -r '.PubliclyAccessible')

if [ "$PUBLICLY_ACCESSIBLE" = "true" ]; then
  log_error "RDS instance is publicly accessible (should be false)"
  exit 2
fi

log_check "rds_not_publicly_accessible" "pass" "PubliclyAccessible: $PUBLICLY_ACCESSIBLE"
echo "✓ RDS is NOT publicly accessible"

# Get EC2 security group
echo "[*] Getting EC2 instance security group..."
EC2_SG=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || echo "")

if [ -z "$EC2_SG" ]; then
  log_error "Could not retrieve EC2 security group"
  exit 1
fi

echo "[*] EC2 Security Group: $EC2_SG"

# Check 3: RDS has security group attached
echo "[*] Checking RDS has security group attached..."
RDS_SGs=$(echo "$DB_INFO" | jq -r '.VpcSecurityGroups[].VpcSecurityGroupId' | tr '\n' ' ')

if [ -z "$RDS_SGs" ]; then
  log_error "RDS has no security groups attached"
  exit 2
fi

log_check "rds_has_security_group" "pass" "Security Groups: $RDS_SGs"
echo "✓ RDS has security group(s): $RDS_SGs"

# Get EC2 VPC
echo "[*] Checking EC2 and RDS are in same VPC..."
EC2_VPC=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query 'Reservations[0].Instances[0].VpcId' \
  --output text 2>/dev/null || echo "")

RDS_VPC=$(echo "$DB_INFO" | jq -r '.DBSubnetGroup.VpcId')

if [ "$EC2_VPC" != "$RDS_VPC" ]; then
  # Different VPCs - check if they're connected
  log_error "EC2 ($EC2_VPC) and RDS ($RDS_VPC) are in different VPCs. Cannot add SG-to-SG rule across VPCs without VPC peering."
  log_check "vpcs_same" "fail" "EC2 VPC: $EC2_VPC, RDS VPC: $RDS_VPC"
  exit 2
fi

log_check "vpcs_same" "pass" "Both in VPC: $EC2_VPC"
echo "✓ EC2 and RDS are in same VPC"

# Check 4: RDS security group has SG-to-SG rule from EC2
echo "[*] Checking for security group-to-security group rule..."
RDS_SG=$(echo "$RDS_SGs" | awk '{print $1}')

# Get the RDS SG details
RDS_SG_DETAILS=$(aws ec2 describe-security-groups \
  --group-ids "$RDS_SG" \
  --region "$REGION" \
  --output json 2>/dev/null || echo "{}")

# Check ingress rules for reference to EC2 SG
SG_TO_SG_FOUND=false

# Check both old and new API formats
if echo "$RDS_SG_DETAILS" | jq -e ".SecurityGroups[0].IpPermissions[] | select(.UserIdGroupPairs[].GroupId == \"$EC2_SG\")" > /dev/null 2>&1; then
  SG_TO_SG_FOUND=true
fi

# Also try the newer format
if [ "$SG_TO_SG_FOUND" = false ]; then
  if echo "$RDS_SG_DETAILS" | jq -e ".SecurityGroups[0].IpPermissions[] | select(.ReferencedGroupInfo.GroupId == \"$EC2_SG\")" > /dev/null 2>&1; then
    SG_TO_SG_FOUND=true
  fi
fi

if [ "$SG_TO_SG_FOUND" = false ]; then
  log_error "RDS security group does not have SG-to-SG rule from EC2 security group $EC2_SG"
  exit 2
fi

log_check "rds_sg_to_sg_rule_exists" "pass" "EC2 SG $EC2_SG has ingress to RDS SG $RDS_SG"
echo "✓ RDS security group has SG-to-SG ingress rule from EC2"

# Check 5: Get and verify RDS port
echo "[*] Checking RDS port..."
if [ -z "$DB_PORT" ]; then
  DB_PORT=$(echo "$DB_INFO" | jq -r '.Endpoint.Port')
fi

if [ -z "$DB_PORT" ] || [ "$DB_PORT" = "null" ]; then
  log_error "Could not determine RDS port"
  exit 1
fi

log_check "rds_port_identified" "pass" "Port: $DB_PORT"
echo "✓ RDS port: $DB_PORT"

# Check 6: Verify port in SG rule matches
echo "[*] Verifying port in security group rule..."

# Get port from SG rule
PORT_IN_RULE=$(echo "$RDS_SG_DETAILS" | jq -r ".SecurityGroups[0].IpPermissions[] | select(.UserIdGroupPairs[].GroupId == \"$EC2_SG\" or .ReferencedGroupInfo.GroupId == \"$EC2_SG\") | .FromPort" | head -1)

if [ -z "$PORT_IN_RULE" ] || [ "$PORT_IN_RULE" = "null" ]; then
  # Port not restricted (wildcard)
  log_check "rds_port_in_sg_rule" "pass" "Port access unrestricted (all ports allowed via SG rule)"
  echo "✓ Port access is allowed via security group rule"
else
  if [ "$PORT_IN_RULE" = "$DB_PORT" ] || [ "$PORT_IN_RULE" = "-1" ]; then
    log_check "rds_port_in_sg_rule" "pass" "Port $DB_PORT in SG ingress rule"
    echo "✓ RDS port is allowed in security group rule"
  else
    log_error "Security group rule port ($PORT_IN_RULE) does not match RDS port ($DB_PORT)"
    exit 2
  fi
fi

# Check 7 (Optional): Verify RDS is in private subnets
if [ "$CHECK_PRIVATE_SUBNETS" = "true" ]; then
  echo "[*] Checking RDS subnets are private (no IGW routes)..."
  
  RDS_SUBNET_GROUP=$(echo "$DB_INFO" | jq -r '.DBSubnetGroup.DBSubnetGroupName')
  RDS_SUBNETS=$(echo "$DB_INFO" | jq -r '.DBSubnetGroup.Subnets[].SubnetId' | tr '\n' ' ')
  
  if [ -z "$RDS_SUBNETS" ]; then
    log_error "Could not determine RDS subnets"
    exit 1
  fi
  
  ALL_PRIVATE=true
  for subnet in $RDS_SUBNETS; do
    # Check route table for IGW route
    IGW_ROUTE=$(aws ec2 describe-route-tables \
      --filters "Name=association.subnet-id,Values=$subnet" \
      --region "$REGION" \
      --query 'RouteTables[0].Routes[?GatewayId!=null && starts_with(GatewayId, `igw`)].GatewayId' \
      --output text 2>/dev/null || echo "")
    
    if [ -n "$IGW_ROUTE" ]; then
      ALL_PRIVATE=false
      log_error "RDS subnet $subnet has direct IGW route (should be private)"
    fi
  done
  
  if [ "$ALL_PRIVATE" = true ]; then
    log_check "rds_subnets_private" "pass" "All RDS subnets are private: $RDS_SUBNETS"
    echo "✓ All RDS subnets are private (no IGW routes)"
  else
    exit 2
  fi
fi

# Final status
echo ""
echo "=========================================="
if jq -r '.passed' "$OUTPUT_FILE" | grep -q "true"; then
  echo "✅ All checks passed"
  exit 0
else
  echo "❌ Some checks failed"
  exit 2
fi
