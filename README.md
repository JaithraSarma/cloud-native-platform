# Cloud-Native Microservices Deployment Platform

A production-grade, multi-tier microservices platform running on **Azure Kubernetes Service (AKS)**, built exclusively with **Azure-native services** — zero third-party tooling.

Live-tested locally with Docker Compose (PostgreSQL + Node.js API + React frontend) and fully wired for one-command Azure deployment via Terraform + Kustomize + Azure DevOps Pipelines.

---

## High-Level Architecture

```
                            ┌──────────────────────────────────────────────┐
                            │              AZURE CLOUD                     │
                            │                                              │
  Users ──► Internet ──►    │  ┌────────────────────────────────────────┐  │
                            │  │     Azure Kubernetes Service (AKS)     │  │
                            │  │                                        │  │
                            │  │   ┌─── AKS Web App Routing ──────┐    │  │
                            │  │   │    (Managed NGINX Ingress)    │    │  │
                            │  │   └──┬───────────────────────┬───┘    │  │
                            │  │      │ /api, /health, /metrics│ /     │  │
                            │  │      ▼                        ▼       │  │
                            │  │  ┌────────────┐      ┌────────────┐   │  │
                            │  │  │  API Pod    │      │ Frontend   │   │  │
                            │  │  │  Node.js    │      │ React/Nginx│   │  │
                            │  │  │  Express    │      │ Dashboard  │   │  │
                            │  │  │  Port 3001  │      │ Port 80    │   │  │
                            │  │  └──────┬─────┘      └────────────┘   │  │
                            │  │         │                              │  │
                            │  │  ┌──────▼──────────────────────────┐   │  │
                            │  │  │  Key Vault CSI Volume Mounts   │   │  │
                            │  │  │  (Secrets rotated every 2min)  │   │  │
                            │  │  └────────────────────────────────┘   │  │
                            │  │                                        │  │
                            │  │  Container Insights ──► Log Analytics  │  │
                            │  │  Metric Alerts (CPU/Memory > 80%)      │  │
                            │  └────────────────────────────────────────┘  │
                            │                                              │
                            │  ┌─────────────┐  ┌──────────────────────┐  │
                            │  │  Azure       │  │  Azure PostgreSQL    │  │
                            │  │  Container   │  │  Flexible Server     │  │
                            │  │  Registry    │  │  (v16, SSL-only)     │  │
                            │  │  (ACR)       │  │                      │  │
                            │  └─────────────┘  └──────────────────────┘  │
                            │                                              │
                            │  ┌─────────────┐  ┌──────────────────────┐  │
                            │  │  Azure       │  │  Azure Monitor       │  │
                            │  │  Key Vault   │  │  + Action Groups     │  │
                            │  │  (RBAC mode) │  │  + Metric Alerts     │  │
                            │  └─────────────┘  └──────────────────────┘  │
                            └──────────────────────────────────────────────┘
```

## Docker Compose Architecture (Local Development)

```
  ┌──────────────────────────────────────────────────────────┐
  │                  docker-compose.yml                       │
  │                                                          │
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
  │  │  PostgreSQL   │  │   API        │  │  Frontend    │   │
  │  │  16-alpine    │  │  Node.js 20  │  │  React+Nginx │   │
  │  │  Port: 5432   │──│  Port: 3001  │──│  Port: 8080  │   │
  │  │  Volume:      │  │  Helmet      │  │  SPA routing │   │
  │  │  pgdata       │  │  Rate-limit  │  │  /api proxy  │   │
  │  │               │  │  Prometheus  │  │              │   │
  │  └──────────────┘  └──────────────┘  └──────────────┘   │
  │                                                          │
  │              Network: app-network (bridge)               │
  └──────────────────────────────────────────────────────────┘
```

## CI/CD Pipeline Architecture

```
  ┌───────────────────── Azure DevOps Pipelines ─────────────────────┐
  │                                                                   │
  │  ci-pipeline.yaml                                                 │
  │  ┌───────────┐    ┌───────────────┐    ┌──────────────┐          │
  │  │ Build &   │───►│ Build Docker  │───►│ Security     │          │
  │  │ Test      │    │ Images → ACR  │    │ Scan (Trivy) │          │
  │  │ (npm test)│    │ (api+frontend)│    │              │          │
  │  └───────────┘    └───────────────┘    └──────────────┘          │
  │                                                                   │
  │  cd-pipeline.yaml                                                 │
  │  ┌───────────┐    ┌───────────────┐    ┌──────────────┐          │
  │  │ Deploy    │───►│ Deploy        │───►│ Deploy       │          │
  │  │ Dev (auto)│    │ Staging       │    │ Prod         │          │
  │  │           │    │ (approval)    │    │ (approval)   │          │
  │  └───────────┘    └───────────────┘    └──────────────┘          │
  │                                                                   │
  │  infra-pipeline.yaml                                              │
  │  ┌───────────┐    ┌───────────────┐    ┌──────────────┐          │
  │  │ Validate  │───►│ Plan + Apply  │───►│ Plan + Apply │          │
  │  │ (fmt/val) │    │ Dev           │    │ Prod         │          │
  │  └───────────┘    └───────────────┘    └──────────────┘          │
  └───────────────────────────────────────────────────────────────────┘
```

## Kubernetes Deployment Architecture

```
  ┌───────────────────── Kustomize Structure ─────────────────────┐
  │                                                                │
  │  k8s/base/                    k8s/overlays/                    │
  │  ┌─────────────────────┐     ┌──────────────────────────────┐ │
  │  │ namespace.yaml      │     │ dev/                          │ │
  │  │ api-deployment.yaml │     │   1 replica, low resources    │ │
  │  │ api-service.yaml    │────►│ staging/                      │ │
  │  │ frontend-deploy.yaml│     │   2 replicas, mid resources   │ │
  │  │ frontend-svc.yaml   │     │ prod/                         │ │
  │  │ ingress.yaml        │     │   3 replicas, HPA (3-10),    │ │
  │  │ secret-provider.yaml│     │   PDB (minAvail: 2),         │ │
  │  └─────────────────────┘     │   high resources              │ │
  │                               └──────────────────────────────┘ │
  └────────────────────────────────────────────────────────────────┘
```

---

## Azure-Native Services Used

| Component | Azure Service | Purpose | Replaces |
|-----------|--------------|---------|----------|
| Container Orchestration | **AKS** (v1.29) | Runs API + Frontend pods, autoscaling, rolling updates | Self-managed K8s |
| Container Registry | **ACR** (Basic/Premium) | Stores Docker images, AKS pulls via managed identity | Docker Hub |
| Ingress Controller | **AKS Web App Routing** | Managed NGINX ingress addon, zero extra pods to manage | Community NGINX Ingress |
| Configuration Management | **Kustomize** (built into kubectl) | Base + overlay K8s manifests per environment | Helm |
| Secrets Management | **Azure Key Vault + CSI Driver** | Mounts secrets as volumes, auto-rotates every 2 min | HashiCorp Vault |
| Monitoring | **Azure Monitor + Container Insights** | Node/pod metrics, log collection to Log Analytics | Prometheus + Grafana |
| Alerting | **Azure Monitor Metric Alerts** | CPU/memory > 80% alerts via Action Groups | Alertmanager |
| Database | **Azure PostgreSQL Flexible Server** (v16) | Managed PostgreSQL with SSL, backups, geo-redundancy | Self-hosted PostgreSQL |
| Secrets Storage | **Azure Key Vault** (RBAC mode) | Stores DB password + connection string | K8s Secrets |
| Infrastructure as Code | **Terraform** (azurerm ~> 4.0) | Provisions all ~14 Azure resources declaratively | ARM Templates |
| CI/CD | **Azure DevOps Pipelines** | 3 pipelines: CI, CD (3-stage), Infrastructure | GitHub Actions / Jenkins |

---

## Project Structure

```
cloud-native-platform/
├── api/                              # Backend microservice
│   ├── src/
│   │   ├── server.js                 # Express app with security middleware
│   │   ├── db.js                     # PostgreSQL pool, migrations, seeding
│   │   └── routes/
│   │       ├── products.js           # CRUD with input validation
│   │       └── health.js             # Liveness/readiness/health probes
│   ├── tests/api.test.js             # Jest API tests
│   ├── Dockerfile                    # Multi-stage build (node:20-alpine)
│   └── package.json                  # Express, pg, helmet, prom-client, etc.
│
├── frontend/                         # Frontend microservice
│   ├── src/
│   │   ├── App.jsx                   # React dashboard (stats, CRUD table, health polling)
│   │   ├── main.jsx                  # React entry point
│   │   └── index.css                 # Tailwind CSS
│   ├── nginx.conf                    # Reverse proxy config (/api → api:3001)
│   ├── Dockerfile                    # Multi-stage build (node → nginx:1.25-alpine)
│   ├── vite.config.js                # Vite 5 config
│   └── package.json                  # React 18, Vite, Tailwind CSS
│
├── infra/terraform/                  # Azure infrastructure
│   ├── main.tf                       # 14 Azure resources (RG, ACR, AKS, PG, KV, Monitor)
│   ├── provider.tf                   # azurerm ~> 4.0 with feature flags
│   ├── variables.tf                  # All variable declarations with validation
│   ├── outputs.tf                    # Resource names, FQDNs, connection info
│   └── environments/
│       ├── dev.tfvars                # 2 nodes, B1ms Postgres, 30-day logs
│       ├── staging.tfvars            # 2 nodes, B2s Postgres
│       └── prod.tfvars               # 3 nodes, D2s Postgres, 90-day logs, geo backup
│
├── k8s/                              # Kubernetes manifests (Kustomize)
│   ├── base/                         # Shared resources (7 manifests)
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── api-deployment.yaml       # 2 replicas, rolling update, probes
│   │   ├── api-service.yaml          # ClusterIP on port 3001
│   │   ├── frontend-deployment.yaml
│   │   ├── frontend-service.yaml     # ClusterIP on port 80
│   │   ├── ingress.yaml              # Web App Routing, path-based routing
│   │   └── secret-provider.yaml      # Key Vault CSI SecretProviderClass
│   └── overlays/
│       ├── dev/kustomization.yaml    # 1 replica, reduced resources
│       ├── staging/kustomization.yaml# 2 replicas, moderate resources
│       └── prod/
│           ├── kustomization.yaml    # 3 replicas, high resources, image overrides
│           ├── hpa.yaml              # API: 3-10 pods, Frontend: 3-8 pods
│           └── pdb.yaml              # minAvailable: 2 for both services
│
├── pipelines/                        # Azure DevOps pipeline definitions
│   ├── ci-pipeline.yaml              # Build → Test → Build Images → Security Scan
│   ├── cd-pipeline.yaml              # Dev (auto) → Staging (approval) → Prod (approval)
│   └── infra-pipeline.yaml           # Validate → Plan/Apply Dev → Plan/Apply Prod
│
├── scripts/                          # Automation scripts
│   ├── setup-azure.sh                # Full provisioning: TF state → Terraform → ACR → AKS deploy
│   ├── teardown.sh                   # Destroy all resources (with confirmation)
│   └── local-dev.sh                  # Docker Compose startup with health check
│
├── docker-compose.yml                # 3 services: db, api, frontend on bridge network
├── .gitignore
├── README.md                         # ← You are here
└── READMEEXPLAINED.md                # Interview prep & deep technical explanation
```

---

## Getting Started

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Docker Desktop | Latest | https://docs.docker.com/desktop/install/windows-install/ |
| Node.js | 20.x LTS | https://nodejs.org/ |
| Git | Latest | https://git-scm.com/ |
| Azure CLI | Latest | `winget install Microsoft.AzureCLI` |
| Terraform | >= 1.5 | `winget install Hashicorp.Terraform` |
| kubectl | Latest | `az aks install-cli` |

---

### Option 1: Run Locally with Docker Compose

This is the quickest way to get the full platform running. All three services (PostgreSQL, API, Frontend) run as containers.

```bash
# Clone the repository
git clone <your-repo-url>
cd cloud-native-platform

# Build and start all services
docker compose up --build -d

# Wait ~15 seconds for PostgreSQL health check, then verify
docker compose ps

# Expected output:
# cloudplatform-db        Healthy    0.0.0.0:5432->5432/tcp
# cloudplatform-api       Running    0.0.0.0:3001->3001/tcp
# cloudplatform-frontend  Running    0.0.0.0:8080->80/tcp
```

**Access the running application:**

| Service | URL | Description |
|---------|-----|-------------|
| Frontend Dashboard | http://localhost:8080 | React dashboard with product CRUD and health monitoring |
| API Health | http://localhost:3001/health | Full health check (API + database status) |
| API Products | http://localhost:3001/api/products | RESTful products endpoint (8 seeded items) |
| Prometheus Metrics | http://localhost:3001/metrics | Application metrics for monitoring |

```bash
# Test the API directly
curl http://localhost:3001/health
# → {"status":"healthy","database":"connected","uptime":...}

curl http://localhost:3001/api/products
# → {"count":8,"products":[...]}

# Create a product
curl -X POST http://localhost:3001/api/products \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Product","price":9.99,"category":"Test"}'

# Shut down everything
docker compose down -v
```

---

### Option 2: Deploy to Azure (Full Cloud Deployment)

This deploys the complete production infrastructure to Azure — AKS cluster, ACR, PostgreSQL, Key Vault, monitoring, and all Kubernetes workloads.

#### Step 1: Authenticate

```bash
# Login to Azure
az login

# Set your subscription (if you have multiple)
az account set --subscription "<your-subscription-id>"

# Verify
az account show --query "{name:name, id:id}" -o table
```

#### Step 2: Create Terraform Variable File

Create a `terraform.tfvars` file (or use the environment-specific files in `infra/terraform/environments/`):

```hcl
# infra/terraform/environments/dev.tfvars is already configured
# For sensitive values, set environment variables:
export TF_VAR_db_admin_username="cloudadmin"
export TF_VAR_db_admin_password="YourSecurePassword123!"  # Change this!
```

#### Step 3: Deploy with the Setup Script

```bash
# Make scripts executable
chmod +x scripts/setup-azure.sh scripts/teardown.sh

# Deploy dev environment to East US 2
./scripts/setup-azure.sh dev eastus2
```

**What the script does:**
1. Creates Azure Storage Account for Terraform remote state
2. Runs `terraform init` with Azure backend configuration
3. Runs `terraform plan` then `terraform apply` — provisions AKS, ACR, PostgreSQL, Key Vault, Monitor
4. Configures `kubectl` with AKS credentials
5. Logs into ACR, builds and pushes Docker images
6. Deploys Kubernetes workloads with `kubectl apply -k k8s/overlays/dev`

#### Step 4: Verify the Deployment

```bash
# Check all pods are running
kubectl get pods -n cloud-platform-dev

# Get the public IP (from AKS Web App Routing ingress)
kubectl get ingress -n cloud-platform-dev

# Test the API through the ingress
curl http://<EXTERNAL-IP>/health
curl http://<EXTERNAL-IP>/api/products
```

#### Step 5: Teardown (Save Your Credits!)

```bash
# Destroy all Azure resources
./scripts/teardown.sh dev
# Type 'yes' when prompted to confirm
```

#### Manual Terraform Commands (Alternative)

```bash
cd infra/terraform

# Initialize
terraform init

# Plan (review what will be created)
terraform plan -var-file="environments/dev.tfvars" \
  -var="db_admin_username=cloudadmin" \
  -var="db_admin_password=YourPassword123!"

# Apply
terraform apply -var-file="environments/dev.tfvars" \
  -var="db_admin_username=cloudadmin" \
  -var="db_admin_password=YourPassword123!"

# Destroy
terraform destroy -var-file="environments/dev.tfvars" \
  -var="db_admin_username=cloudadmin" \
  -var="db_admin_password=YourPassword123!"
```

---

## API Reference

### Health & Monitoring

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Full health check — returns API status, DB connection, uptime, memory usage, hostname |
| GET | `/health/live` | Kubernetes liveness probe — returns `{"status":"alive"}` if process is running |
| GET | `/health/ready` | Kubernetes readiness probe — returns 200 only if database is connected |
| GET | `/metrics` | Prometheus-format metrics for scraping (default Node.js + custom metrics) |

### Product CRUD

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/products` | List all products. Supports `?category=Infrastructure&sort=price&in_stock=true` |
| GET | `/api/products/:id` | Get a single product by ID |
| POST | `/api/products` | Create a product. Body: `{name, price, description?, category?, in_stock?}` |
| PUT | `/api/products/:id` | Update a product. Body: same as POST |
| DELETE | `/api/products/:id` | Delete a product. Returns the deleted product |

### API Security

- **Helmet** — Sets security HTTP headers (X-Content-Type-Options, X-Frame-Options, etc.)
- **CORS** — Configurable origin, methods, headers
- **Rate Limiting** — 100 requests per 15 minutes per IP on `/api/*`
- **Input Validation** — express-validator with sanitization (trim, escape, length checks)
- **JSON Body Limit** — 10kb max payload size
- **Parameterized Queries** — All SQL uses `$1, $2` placeholders, preventing SQL injection

---

## Azure Resources Provisioned by Terraform

When you run `terraform apply`, these 14 resources are created:

| # | Resource | Name Pattern | Purpose |
|---|----------|-------------|---------|
| 1 | Resource Group | `rg-cloudplatform-dev` | Container for all resources |
| 2 | Container Registry | `acrcloudplatformdev` | Docker image storage |
| 3 | Log Analytics Workspace | `law-cloudplatform-dev` | Central log aggregation |
| 4 | AKS Cluster | `aks-cloudplatform-dev` | Kubernetes with 3 addons enabled |
| 5 | AKS → ACR Role Assignment | — | `AcrPull` for kubelet identity |
| 6 | Key Vault | `kv-cloudplatform-dev` | Secrets storage (RBAC mode) |
| 7 | AKS → KV Role Assignment | — | `Key Vault Secrets User` for CSI driver |
| 8 | Deployer → KV Role Assignment | — | `Key Vault Administrator` for Terraform |
| 9 | Key Vault Secret | `db-password` | PostgreSQL admin password |
| 10 | Key Vault Secret | `db-host` | PostgreSQL FQDN |
| 11 | Key Vault Secret | `db-user` | PostgreSQL admin username |
| 12 | Key Vault Secret | `db-connection-string` | Full PostgreSQL connection URI |
| 13 | PostgreSQL Flexible Server | `psql-cloudplatform-dev` | Managed database (v16) |
| 14 | PostgreSQL Database | `cloudplatform` | Application database |
| 15 | PostgreSQL Firewall Rule | `AllowAzureServices` | Allows AKS → PostgreSQL traffic |
| 16 | Monitor Action Group | `ag-cloudplatform-dev-critical` | Alert notification target |
| 17 | CPU Metric Alert | `alert-cloudplatform-dev-high-cpu` | Fires when node CPU > 80% |
| 18 | Memory Metric Alert | `alert-cloudplatform-dev-high-memory` | Fires when node memory > 80% |

---

## Environment Configurations

| Setting | Dev | Staging | Prod |
|---------|-----|---------|------|
| AKS Nodes | 2 (max 5) | 2 (max 6) | 3 (max 10) |
| AKS VM Size | Standard_D2s_v5 | Standard_D2s_v5 | Standard_D4s_v5 |
| PostgreSQL SKU | B_Standard_B1ms | B_Standard_B2s | D_Standard_D2s_v3 |
| PostgreSQL Storage | 32 GB | 64 GB | 128 GB |
| Log Retention | 30 days | 30 days | 90 days |
| ACR SKU | Basic | Basic | Premium |
| Availability Zones | None | None | 1, 2, 3 |
| Geo-Redundant Backup | No | No | Yes |
| K8s Replicas (API) | 1 | 2 | 3 (HPA 3-10) |
| Pod Disruption Budget | None | None | minAvailable: 2 |

---

## Tech Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Frontend | React + Vite + Tailwind CSS | 18 / 5 / 3 |
| Frontend Server | Nginx (Alpine) | 1.25 |
| Backend | Node.js + Express | 20 / 4.18 |
| Database | PostgreSQL | 16 |
| Container Runtime | Docker (multi-stage builds) | Latest |
| Orchestration | Kubernetes (AKS) | 1.29 |
| Configuration | Kustomize | Built-in kubectl |
| Infrastructure | Terraform (azurerm provider) | >= 1.5 / ~> 4.0 |
| CI/CD | Azure DevOps Pipelines | — |
| Security Scanning | Trivy (container image scan) | Latest |

---

## License

MIT
