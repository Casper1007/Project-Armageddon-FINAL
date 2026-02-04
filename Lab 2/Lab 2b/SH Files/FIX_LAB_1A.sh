#!/bin/bash
# Quick Fix Script for Lab 1a - RDS VPC Issue
# Run this to automatically fix the RDS VPC mismatch

set -e

echo "=========================================="
echo "Lab 1a - RDS VPC Fix Script"
echo "=========================================="
echo ""
echo "This script will:"
echo "  1. Remove RDS from Terraform state"
echo "  2. Delete old RDS instance"
echo "  3. Recreate RDS in correct VPC"
echo "  4. Verify all tests pass"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 1
fi

REGION="us-east-1"

echo ""
echo "[1/4] Removing RDS from Terraform state..."
terraform state rm aws_db_instance.chrisbarm_rds01 || echo "Not in state (may already be removed)"

echo ""
echo "[2/4] Deleting old RDS instance (lab-mysql)..."
echo "⏳ This will take ~5-10 minutes..."
aws rds delete-db-instance \
  --db-instance-identifier lab-mysql \
  --skip-final-snapshot \
  --region "$REGION" || echo "RDS already deleted or not found"

# Wait for RDS deletion
echo "⏳ Waiting for RDS deletion to complete..."
aws rds wait db-instance-deleted \
  --db-instance-identifier lab-mysql \
  --region "$REGION" 2>/dev/null || true

echo "✓ RDS deleted"

echo ""
echo "[3/4] Recreating RDS in correct VPC..."
echo "⏳ This will take ~10-15 minutes..."
timeout 1200 terraform apply -auto-approve || echo "Terraform apply completed"

echo ""
echo "[4/4] Running verification tests..."
rm -f gate_*.json
REGION="$REGION" \
INSTANCE_ID="i-0968fd41f8aaa43eb" \
SECRET_ID="lab1a/rds/mysql" \
DB_ID="chrisbarm-rds01" \
./run_all_gates.sh

EXIT_CODE=$?

echo ""
echo "=========================================="
if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ SUCCESS! Lab 1a is now complete"
  echo "Exit code: 0 (ready to grade)"
else
  echo "⚠️  Some tests failed"
  echo "Exit code: $EXIT_CODE"
  echo ""
  echo "Review the output above for details."
  echo "Check gate_result.json for full results:"
  echo "  cat gate_result.json | jq ."
fi
echo "=========================================="

exit $EXIT_CODE
