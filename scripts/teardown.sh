#!/bin/bash
set -euo pipefail

# ============================================================================
# Teardown Azure Infrastructure
# ============================================================================

ENV="${1:-dev}"
PROJECT="cloudplatform"

echo "=== DESTROYING $ENV environment ==="
echo "This will delete ALL resources for cloud-platform-$ENV"
read -p "Type 'yes' to confirm: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

cd infra/terraform

terraform init \
  -backend-config="resource_group_name=tfstate-rg" \
  -backend-config="storage_account_name=tfstate${PROJECT}${ENV}" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=${ENV}.tfstate"

terraform destroy -var-file="environments/${ENV}.tfvars" -auto-approve

echo "=== Teardown complete ==="
