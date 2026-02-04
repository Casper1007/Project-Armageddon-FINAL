#!/bin/bash
###############################################################################
# run_all_gates.sh
# Master script to run all verification gates and combine results
# Exit codes: 0=pass, 2=fail, 1=error
###############################################################################

set -euo pipefail

REGION="${REGION:-us-east-1}"
INSTANCE_ID="${INSTANCE_ID:-}"
SECRET_ID="${SECRET_ID:-}"
DB_ID="${DB_ID:-}"
CHECK_SECRET_VALUE_READ="${CHECK_SECRET_VALUE_READ:-false}"
REQUIRE_ROTATION="${REQUIRE_ROTATION:-false}"
CHECK_PRIVATE_SUBNETS="${CHECK_PRIVATE_SUBNETS:-false}"
DB_PORT="${DB_PORT:-}"

# Validate required inputs
if [ -z "$INSTANCE_ID" ] || [ -z "$SECRET_ID" ] || [ -z "$DB_ID" ]; then
  echo "[ERROR] Missing required environment variables"
  echo "Required: REGION, INSTANCE_ID, SECRET_ID, DB_ID"
  exit 1
fi

echo "=========================================="
echo "Lab 1a Verification Suite"
echo "=========================================="
echo "Region: $REGION"
echo "Instance ID: $INSTANCE_ID"
echo "Secret ID: $SECRET_ID"
echo "DB ID: $DB_ID"
echo ""

# Ensure scripts are executable
chmod +x gate_secrets_and_role.sh 2>/dev/null || true
chmod +x gate_network_db.sh 2>/dev/null || true

# Run gate_secrets_and_role.sh
echo "[1/2] Running gate_secrets_and_role.sh..."
export REGION INSTANCE_ID SECRET_ID CHECK_SECRET_VALUE_READ REQUIRE_ROTATION
if ./gate_secrets_and_role.sh; then
  echo "✓ Secrets and role verification passed"
  GATE1_PASS=true
else
  echo "✗ Secrets and role verification failed"
  GATE1_PASS=false
fi

echo ""

# Run gate_network_db.sh
echo "[2/2] Running gate_network_db.sh..."
export REGION INSTANCE_ID DB_ID CHECK_PRIVATE_SUBNETS DB_PORT
if ./gate_network_db.sh; then
  echo "✓ Network and DB verification passed"
  GATE2_PASS=true
else
  echo "✗ Network and DB verification failed"
  GATE2_PASS=false
fi

echo ""
echo "=========================================="
echo "Combining Results..."
echo "=========================================="

# Combine results into gate_result.json
cat > gate_result.json << EOF
{
  "suite": "Lab 1a Complete Verification",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "$REGION",
  "instance_id": "$INSTANCE_ID",
  "secret_id": "$SECRET_ID",
  "db_id": "$DB_ID",
  "tests": {},
  "overall_passed": false,
  "exit_code": 1
}
EOF

# Merge individual test results
if [ -f "gate_secrets_and_role.json" ]; then
  jq ".tests.gate_secrets_and_role = $(cat gate_secrets_and_role.json)" gate_result.json > gate_result.json.tmp && mv gate_result.json.tmp gate_result.json
fi

if [ -f "gate_network_db.json" ]; then
  jq ".tests.gate_network_db = $(cat gate_network_db.json)" gate_result.json > gate_result.json.tmp && mv gate_result.json.tmp gate_result.json
fi

# Determine overall status
OVERALL_PASS=true
if [ "$GATE1_PASS" != "true" ] || [ "$GATE2_PASS" != "true" ]; then
  OVERALL_PASS=false
fi

if [ "$OVERALL_PASS" = true ]; then
  jq ".overall_passed = true | .exit_code = 0" gate_result.json > gate_result.json.tmp && mv gate_result.json.tmp gate_result.json
  EXIT_CODE=0
else
  jq ".overall_passed = false | .exit_code = 2" gate_result.json > gate_result.json.tmp && mv gate_result.json.tmp gate_result.json
  EXIT_CODE=2
fi

echo ""
echo "=========================================="
if [ "$OVERALL_PASS" = true ]; then
  echo "✅ ALL GATES PASSED - Ready for merge/grade"
  echo "Exit code: 0"
else
  echo "❌ SOME GATES FAILED - Review output above"
  echo "Exit code: 2"
fi
echo "=========================================="
echo ""
echo "Results saved to:"
echo "  - gate_secrets_and_role.json"
echo "  - gate_network_db.json"
echo "  - gate_result.json (summary)"
echo ""

exit $EXIT_CODE
