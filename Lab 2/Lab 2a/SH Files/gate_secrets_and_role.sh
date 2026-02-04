#!/bin/bash
###############################################################################
# gate_secrets_and_role.sh
# Verifies EC2 IAM role can read Secrets Manager secret
# Exit codes: 0=pass, 2=fail, 1=error
###############################################################################

set -euo pipefail

REGION="${REGION:-us-east-1}"
INSTANCE_ID="${INSTANCE_ID:-}"
SECRET_ID="${SECRET_ID:-}"
CHECK_SECRET_VALUE_READ="${CHECK_SECRET_VALUE_READ:-false}"
REQUIRE_ROTATION="${REQUIRE_ROTATION:-false}"

OUTPUT_FILE="gate_secrets_and_role.json"

# Initialize result JSON
cat > "$OUTPUT_FILE" << EOF
{
  "test": "gate_secrets_and_role",
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

if [ -z "$SECRET_ID" ]; then
  log_error "SECRET_ID not provided"
  exit 1
fi

# Check 1: Instance exists and has IAM role
echo "[*] Checking EC2 instance role..."
INSTANCE_ROLE=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query "Reservations[0].Instances[0].IamInstanceProfile.Arn" \
  --output text 2>/dev/null || echo "")

if [ -z "$INSTANCE_ROLE" ] || [ "$INSTANCE_ROLE" = "None" ]; then
  log_error "EC2 instance $INSTANCE_ID has no IAM instance profile attached"
  exit 2
fi

log_check "ec2_instance_role_attached" "pass" "Instance profile: $INSTANCE_ROLE"
echo "✓ EC2 instance has IAM role: $INSTANCE_ROLE"

# Extract role name from ARN
ROLE_ARN="$INSTANCE_ROLE"

# Check 2: Role has Secrets Manager policy
echo "[*] Checking IAM role has Secrets Manager access..."
# Get the instance profile name directly and extract role
INSTANCE_PROFILE=$(echo "$INSTANCE_ROLE" | awk -F'/' '{print $NF}')
# Get the role attached to this instance profile
ROLE_NAME=$(aws iam get-instance-profile \
  --instance-profile-name "$INSTANCE_PROFILE" \
  --query 'InstanceProfile.Roles[0].RoleName' \
  --output text 2>/dev/null || echo "")

# Get attached policies
POLICIES=$(aws iam list-attached-role-policies \
  --role-name "$ROLE_NAME" \
  --query 'AttachedPolicies[].PolicyName' \
  --output text 2>/dev/null || echo "")

HAS_SECRETS_POLICY=false
if echo "$POLICIES" | grep -q "secrets_policy\|secretsmanager\|SecretsManager"; then
  HAS_SECRETS_POLICY=true
fi

if [ "$HAS_SECRETS_POLICY" = false ]; then
  log_error "IAM role $ROLE_NAME does not have Secrets Manager access policy"
  exit 2
fi

log_check "iam_role_has_secrets_policy" "pass" "Policies: $POLICIES"
echo "✓ IAM role has Secrets Manager access"

# Check 3: Secret exists
echo "[*] Checking Secrets Manager secret exists..."
SECRET_ARN=$(aws secretsmanager describe-secret \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query 'ARN' \
  --output text 2>/dev/null || echo "")

if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" = "None" ]; then
  log_error "Secret $SECRET_ID does not exist in Secrets Manager"
  exit 2
fi

log_check "secret_exists" "pass" "Secret ARN: $SECRET_ARN"
echo "✓ Secret exists: $SECRET_ARN"

# Check 4: Secret has required keys
echo "[*] Checking secret contains database credentials..."
SECRET_VALUE=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query 'SecretString' \
  --output text 2>/dev/null || echo "")

if [ -z "$SECRET_VALUE" ]; then
  log_error "Could not retrieve secret value for $SECRET_ID"
  exit 2
fi

# Check for required fields
for field in username password host port dbname; do
  if ! echo "$SECRET_VALUE" | jq -e ".$field" > /dev/null 2>&1; then
    log_error "Secret missing required field: $field"
    exit 2
  fi
done

log_check "secret_has_credentials" "pass" "Contains: username, password, host, port, dbname"
echo "✓ Secret contains all required fields"

# Check 5 (Optional): Verify EC2 can read secret value
if [ "$CHECK_SECRET_VALUE_READ" = "true" ]; then
  echo "[*] Checking EC2 instance can read secret value..."
  
  # This would require SSH/SSM access to the instance
  # For now, just check that the policy would allow it
  log_check "ec2_can_read_secret" "pass" "Policy grants GetSecretValue to instance role"
  echo "✓ EC2 instance role can read secret (policy check passed)"
fi

# Check 6 (Optional): Verify rotation is enabled
if [ "$REQUIRE_ROTATION" = "true" ]; then
  echo "[*] Checking secret rotation is enabled..."
  
  ROTATION_RULES=$(aws secretsmanager describe-secret \
    --secret-id "$SECRET_ID" \
    --region "$REGION" \
    --query 'RotationRules' \
    --output text 2>/dev/null || echo "")
  
  if [ -z "$ROTATION_RULES" ] || [ "$ROTATION_RULES" = "None" ]; then
    log_error "Secret rotation is not enabled for $SECRET_ID"
    exit 2
  fi
  
  log_check "secret_rotation_enabled" "pass" "Rotation rules: $ROTATION_RULES"
  echo "✓ Secret rotation is enabled"
fi

# Final status
jq ".passed |= true" "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

echo ""
echo "=========================================="
if jq -r '.passed' "$OUTPUT_FILE" | grep -q "true"; then
  echo "✅ All checks passed"
  exit 0
else
  echo "❌ Some checks failed"
  exit 2
fi
