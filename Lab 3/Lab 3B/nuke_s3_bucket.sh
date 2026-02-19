#!/bin/bash
# Fully empty and delete a versioned S3 bucket (all versions and delete markers)
# Usage: ./nuke_s3_bucket.sh <bucket-name>

set -e
BUCKET="$1"
if [ -z "$BUCKET" ]; then
  echo "Usage: $0 <bucket-name>"
  exit 1
fi

echo "Listing all object versions and delete markers in $BUCKET..."
VERSIONS=$(aws s3api list-object-versions --bucket "$BUCKET" --output json)

# Delete all versions
echo "$VERSIONS" | jq -c '.Versions[]?' | while read -r ver; do
  KEY=$(echo "$ver" | jq -r .Key)
  VERSION_ID=$(echo "$ver" | jq -r .VersionId)
  echo "Deleting version: $KEY ($VERSION_ID)"
  aws s3api delete-object --bucket "$BUCKET" --key "$KEY" --version-id "$VERSION_ID"
done

# Delete all delete markers
echo "$VERSIONS" | jq -c '.DeleteMarkers[]?' | while read -r del; do
  KEY=$(echo "$del" | jq -r .Key)
  VERSION_ID=$(echo "$del" | jq -r .VersionId)
  echo "Deleting delete marker: $KEY ($VERSION_ID)"
  aws s3api delete-object --bucket "$BUCKET" --key "$KEY" --version-id "$VERSION_ID"
done

echo "Attempting to remove bucket $BUCKET..."
aws s3 rb s3://$BUCKET --force
