#!/usr/bin/env bash
# Empty all objects, versions, and delete markers from S3 buckets before Terraform destroy
# Usage: ./empty_s3_buckets.sh bucket1 bucket2 ...
set -euo pipefail

if ! command -v aws &> /dev/null; then
  echo "AWS CLI not found. Please install it first."
  exit 1
fi

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <bucket1> [bucket2 ...]"
  exit 1
fi

for bucket in "$@"; do
  echo "Emptying bucket: $bucket"
  # Remove all object versions
  aws s3api list-object-versions --bucket "$bucket" --output json \
    | jq -r '.Versions[]?, .DeleteMarkers[]? | select(.VersionId != null) | "--key \"\(.Key)\" --version-id \"\(.VersionId)\""' \
    | xargs -r -n4 aws s3api delete-object --bucket "$bucket"
  echo "Bucket $bucket emptied."
done
