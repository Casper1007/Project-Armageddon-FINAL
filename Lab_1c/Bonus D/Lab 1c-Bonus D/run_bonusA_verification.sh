#!/bin/bash
# Script: run_bonusA_verification.sh
# Description: Run AWS CLI checks for Bonus-A and append output to 1c_BonusA_outputs.tf

INSTANCE_ID="$1"   # Pass as first argument
VPC_ID="$2"        # Pass as second argument
OUTPUT_FILE="1c_BonusA_outputs.tf"

{
echo "# Bonus-A Verification Outputs"

# 1) Prove EC2 is private (no public IP)
echo "\n# 1) Prove EC2 is private (no public IP)"
echo "# Command: aws ec2 describe-instances --instance-ids $INSTANCE_ID --query \"Reservations[].Instances[].PublicIpAddress\""
echo "# Output:"
aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query "Reservations[].Instances[].PublicIpAddress"

# 2) Prove VPC endpoints exist
echo "\n# 2) Prove VPC endpoints exist"
echo "# Command: aws ec2 describe-vpc-endpoints --filters \"Name=vpc-id,Values=$VPC_ID\" --query \"VpcEndpoints[].ServiceName\""
echo "# Output:"
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --query "VpcEndpoints[].ServiceName"

# 3) Prove Session Manager path works (no SSH)
echo "\n# 3) Prove Session Manager path works (no SSH)"
echo "# Command: aws ssm describe-instance-information --query \"InstanceInformationList[].InstanceId\""
echo "# Output:"
aws ssm describe-instance-information --query "InstanceInformationList[].InstanceId"

} > "$OUTPUT_FILE"
