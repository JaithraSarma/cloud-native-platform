#!/bin/bash
set -euo pipefail

# ============================================================================
# Setup Azure Infrastructure for Cloud-Native Platform
# ============================================================================

ENV="${1:-dev}"
LOCATION="${2:-eastus2}"
PROJECT="cloudplatform"

echo "=== Setting up $ENV environment in $LOCATION ==="

# Create Terraform state storage
echo "--- Creating Terraform state storage ---"
az group create --name "tfstate-rg" --location "$LOCATION"
az storage account create --name "tfstate${PROJECT}${ENV}" --resource-group "tfstate-rg" \
  --location "$LOCATION" --sku Standard_LRS --encryption-services blob
az storage container create --name "tfstate" --account-name "tfstate${PROJECT}${ENV}"

# Initialize and apply Terraform
echo "--- Running Terraform ---"
cd infra/terraform
terraform init \
  -backend-config="resource_group_name=tfstate-rg" \
  -backend-config="storage_account_name=tfstate${PROJECT}${ENV}" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=${ENV}.tfstate"

terraform plan -var-file="environments/${ENV}.tfvars" -out="${ENV}.tfplan"
terraform apply "${ENV}.tfplan"

# Configure kubectl
echo "--- Configuring kubectl ---"
AKS_NAME=$(terraform output -raw aks_cluster_name)
RG_NAME=$(terraform output -raw resource_group_name)
az aks get-credentials --resource-group "$RG_NAME" --name "$AKS_NAME" --overwrite-existing

# Build and push images
echo "--- Building and pushing images ---"
ACR_NAME=$(terraform output -raw acr_name)
ACR_SERVER=$(terraform output -raw acr_login_server)
az acr login --name "$ACR_NAME"

cd ../..
docker build -t "$ACR_SERVER/cloud-platform-api:${ENV}-latest" ./api
docker build -t "$ACR_SERVER/cloud-platform-frontend:${ENV}-latest" ./frontend
docker push "$ACR_SERVER/cloud-platform-api:${ENV}-latest"
docker push "$ACR_SERVER/cloud-platform-frontend:${ENV}-latest"

# Deploy with Kustomize
echo "--- Deploying to AKS ---"
kubectl apply -k "k8s/overlays/${ENV}"

echo ""
echo "=== Deployment complete! ==="
kubectl get pods -n "cloud-platform-${ENV}"
