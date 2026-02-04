#!/bin/bash
################################################################################
# BONUS-A Deployment Validation Checklist
#
# Run this to validate all Bonus-A components are in place and ready
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                  BONUS-A DEPLOYMENT VALIDATION                            ║"
echo "║                  Checklist for all components                             ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

CHECKS_PASSED=0
CHECKS_FAILED=0

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_file() {
  local file="$1"
  local desc="$2"
  
  if [ -f "$file" ]; then
    echo -e "${GREEN}✓${NC} $desc"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    echo -e "${RED}✗${NC} $desc (MISSING)"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
  fi
}

check_terraform() {
  local file="$1"
  local resource="$2"
  
  if grep -q "resource \"$resource\"" "$file"; then
    echo -e "${GREEN}✓${NC} Terraform: $resource found"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    echo -e "${RED}✗${NC} Terraform: $resource NOT found"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
  fi
}

# File checks
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. TERRAFORM FILES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_file "bonus_a.tf" "bonus_a.tf exists"
echo ""

# Terraform resource checks
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. TERRAFORM RESOURCES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_terraform "bonus_a.tf" "aws_security_group.bonus_a_endpoints_sg"
check_terraform "bonus_a.tf" "aws_security_group.bonus_a_ec2_sg"
check_terraform "bonus_a.tf" "aws_vpc_endpoint.ssm"
check_terraform "bonus_a.tf" "aws_vpc_endpoint.ec2messages"
check_terraform "bonus_a.tf" "aws_vpc_endpoint.ssmmessages"
check_terraform "bonus_a.tf" "aws_vpc_endpoint.logs"
check_terraform "bonus_a.tf" "aws_vpc_endpoint.secretsmanager"
check_terraform "bonus_a.tf" "aws_vpc_endpoint.kms"
check_terraform "bonus_a.tf" "aws_vpc_endpoint.s3"
check_terraform "bonus_a.tf" "aws_instance.bonus_a_ec2"
check_terraform "bonus_a.tf" "aws_iam_role.bonus_a_ec2_role"
check_terraform "bonus_a.tf" "aws_cloudwatch_log_group.bonus_a_logs"
echo ""

# Verification script checks
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. VERIFICATION SCRIPTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_file "verify_bonus_a_1_private_ip.sh" "Test 1: EC2 private"
check_file "verify_bonus_a_2_vpc_endpoints.sh" "Test 2: VPC endpoints"
check_file "verify_bonus_a_3_session_manager.sh" "Test 3: Session Manager"
check_file "verify_bonus_a_4_config_stores.sh" "Test 4: Config stores"
check_file "verify_bonus_a_5_cloudwatch_logs.sh" "Test 5: CloudWatch logs"
check_file "run_bonus_a_verification.sh" "Automation: Run all tests"
echo ""

# Documentation checks
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. DOCUMENTATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_file "BONUS_A_SETUP_GUIDE.md" "Setup guide (full documentation)"
check_file "BONUS_A_QUICK_REFERENCE.md" "Quick reference card"
check_file "BONUS_A_IMPLEMENTATION_SUMMARY.md" "Implementation summary"
check_file "BONUS_A_INDEX.md" "Index & navigation guide"
echo ""

# Size checks (documentation should be substantial)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. DOCUMENTATION QUALITY (Word Count)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "BONUS_A_SETUP_GUIDE.md" ]; then
  SETUP_WORDS=$(wc -w < BONUS_A_SETUP_GUIDE.md)
  if [ "$SETUP_WORDS" -gt 3000 ]; then
    echo -e "${GREEN}✓${NC} Setup guide: $SETUP_WORDS words (comprehensive)"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    echo -e "${YELLOW}⚠${NC} Setup guide: $SETUP_WORDS words (consider expanding)"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
  fi
fi

if [ -f "BONUS_A_QUICK_REFERENCE.md" ]; then
  QUICK_WORDS=$(wc -w < BONUS_A_QUICK_REFERENCE.md)
  if [ "$QUICK_WORDS" -gt 1000 ]; then
    echo -e "${GREEN}✓${NC} Quick reference: $QUICK_WORDS words (complete)"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    echo -e "${YELLOW}⚠${NC} Quick reference: $QUICK_WORDS words (consider expanding)"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
  fi
fi

if [ -f "bonus_a.tf" ]; then
  TERRAFORM_LINES=$(wc -l < bonus_a.tf)
  if [ "$TERRAFORM_LINES" -gt 200 ]; then
    echo -e "${GREEN}✓${NC} Terraform: $TERRAFORM_LINES lines (substantial)"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
  else
    echo -e "${RED}✗${NC} Terraform: $TERRAFORM_LINES lines (too small)"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
  fi
fi

echo ""

# Terraform validation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6. TERRAFORM VALIDATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if terraform fmt -check bonus_a.tf > /dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} Terraform formatting: OK"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  echo -e "${YELLOW}⚠${NC} Terraform formatting: Could be improved"
  echo "  Suggestion: terraform fmt bonus_a.tf"
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

if terraform validate > /dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} Terraform validation: OK"
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
  echo -e "${RED}✗${NC} Terraform validation: FAILED"
  terraform validate
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

echo ""

# Script executability check
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "7. SCRIPT EXECUTABILITY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for script in verify_bonus_a_*.sh run_bonus_a_verification.sh; do
  if [ -f "$script" ]; then
    if head -n 1 "$script" | grep -q "#!/bin/bash"; then
      echo -e "${GREEN}✓${NC} $script has shebang"
      CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
      echo -e "${RED}✗${NC} $script missing shebang"
      CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
  fi
done

echo ""

# Summary
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                           VALIDATION SUMMARY                              ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Checks Passed: ${GREEN}$CHECKS_PASSED${NC}"
echo "  Checks Failed: ${RED}$CHECKS_FAILED${NC}"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ ALL CHECKS PASSED${NC}"
  echo ""
  echo "✅ Bonus-A is ready for deployment!"
  echo ""
  echo "Next steps:"
  echo "  1. terraform apply -auto-approve"
  echo "  2. Wait 2-3 minutes for SSM agent registration"
  echo "  3. Run: bash run_bonus_a_verification.sh <INSTANCE_ID> <VPC_ID>"
  echo ""
  exit 0
else
  echo -e "${RED}✗ SOME CHECKS FAILED${NC}"
  echo ""
  echo "Please review errors above and fix before deployment."
  exit 1
fi
