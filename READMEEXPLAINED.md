# Cloud-Native Microservices Deployment Platform — Interview-Ready Deep Dive

> **Who is this for?** You — the person who built this project. This document gives you the complete technical understanding to confidently explain every decision, every file, and every architecture choice in an interview. It also includes full setup instructions so you can demo the project live.

---

## TABLE OF CONTENTS

1. [How to Get the Project Running](#1-how-to-get-the-project-running)
2. [Project Overview — The Elevator Pitch](#2-project-overview--the-elevator-pitch)
3. [Architecture Decisions — Why This Design](#3-architecture-decisions--why-this-design)
4. [The Three Tiers Explained](#4-the-three-tiers-explained)
5. [Docker & Containerization — What You Built](#5-docker--containerization--what-you-built)
6. [Kubernetes — How It Runs in Production](#6-kubernetes--how-it-runs-in-production)
7. [Kustomize — Why Not Helm?](#7-kustomize--why-not-helm)
8. [Azure-Native Services — Every Service Justified](#8-azure-native-services--every-service-justified)
9. [Terraform — Infrastructure as Code Explained](#9-terraform--infrastructure-as-code-explained)
10. [CI/CD Pipeline Design — From Code to Production](#10-cicd-pipeline-design--from-code-to-production)
11. [Security — Defense in Depth](#11-security--defense-in-depth)
12. [Observability & Monitoring](#12-observability--monitoring)
13. [Networking & Ingress — How Traffic Flows](#13-networking--ingress--how-traffic-flows)
14. [Database Strategy](#14-database-strategy)
15. [Production Readiness Checklist](#15-production-readiness-checklist)
16. [Interview Q&A — 25 Questions You Will Be Asked](#16-interview-qa--25-questions-you-will-be-asked)
17. [Troubleshooting Scenarios](#17-troubleshooting-scenarios)
18. [What Recruiters & Hiring Managers See](#18-what-recruiters--hiring-managers-see)

---

## 1. How to Get the Project Running

### 1.1 Prerequisites

| Tool | Version | Why You Need It | Install Command |
|------|---------|-----------------|-----------------|
| **Docker Desktop** | Latest | Runs all 3 services as containers locally | https://docs.docker.com/desktop/install/windows-install/ |
| **Node.js** | 20.x LTS | Builds the API and frontend during Docker build | https://nodejs.org/ |
| **Git** | Latest | Clone the repo and manage version control | https://git-scm.com/ |
| **Azure CLI** | Latest | Authenticate with Azure and manage resources | `winget install Microsoft.AzureCLI` |
| **Terraform** | >= 1.5 | Provision Azure infrastructure declaratively | `winget install Hashicorp.Terraform` |
| **kubectl** | Latest | Interact with the Kubernetes cluster | `az aks install-cli` |

### 1.2 Option A: Run Locally with Docker Compose (Recommended for Demo)

This runs the full 3-tier application on your machine in containers. Perfect for showing a recruiter.

```powershell
# 1. Clone the repo
git clone <your-repo-url>
cd cloud-native-platform

# 2. Build and start all services (PostgreSQL, API, Frontend)
docker compose up --build -d

# 3. Wait ~15 sec for PostgreSQL health check, then verify
docker compose ps
# Expected:
#   cloudplatform-db        Healthy    0.0.0.0:5432->5432/tcp
#   cloudplatform-api       Running    0.0.0.0:3001->3001/tcp
#   cloudplatform-frontend  Running    0.0.0.0:8080->80/tcp

# 4. Test the API
curl http://localhost:3001/health
# → {"status":"healthy","database":"connected","uptime":...}

curl http://localhost:3001/api/products
# → {"count":8,"products":[...8 seeded products...]}
```

**What to show in the browser:**
- **http://localhost:8080** — Full React dashboard with product table, health indicator, stat cards
- **http://localhost:3001/health** — JSON health check proving DB connectivity
- **http://localhost:3001/api/products** — 8 seeded products loaded from PostgreSQL
- **http://localhost:3001/metrics** — Prometheus metrics endpoint

```powershell
# Shut down and clean up
docker compose down -v
```

**What's happening under the hood:**
- `docker-compose.yml` defines 3 services on a shared bridge network called `app-network`
- PostgreSQL (16-alpine) starts first with a health check (`pg_isready`)
- The API container depends on `db: condition: service_healthy` — it won't start until Postgres responds
- The API auto-creates the `products` table and seeds 8 rows on first boot
- The frontend Nginx container proxies `/api/*` and `/health` requests to the API container
- Volumes (`pgdata`) persist database data across container restarts

### 1.3 Option B: Deploy to Azure (Full Cloud)

This provisions 16 Azure resources, builds/pushes Docker images, and deploys to a live AKS cluster.

**Step 1: Login and configure**
```bash
az login
az account set --subscription "<your-subscription-id>"

# Set sensitive variables (never commit these)
export TF_VAR_db_admin_username="cloudadmin"
export TF_VAR_db_admin_password="YourSecurePassword123!"
```

**Step 2: Run the automated setup script**
```bash
chmod +x scripts/setup-azure.sh
./scripts/setup-azure.sh dev eastus2
```

This single script does everything:
1. Creates an Azure Storage Account for Terraform remote state
2. Runs `terraform init` → `plan` → `apply` (provisions AKS, ACR, PostgreSQL, Key Vault, Monitor)
3. Downloads AKS credentials to your kubeconfig
4. Builds Docker images and pushes them to ACR
5. Deploys K8s manifests with `kubectl apply -k k8s/overlays/dev`

**Step 3: Verify**
```bash
kubectl get pods -n cloud-platform-dev       # All pods Running
kubectl get ingress -n cloud-platform-dev     # Get the public IP
curl http://<EXTERNAL-IP>/health              # Should return healthy
```

**Step 4: Teardown (important for student credits!)**
```bash
./scripts/teardown.sh dev
# Type 'yes' to confirm — destroys ALL Azure resources
```

**Manual Terraform approach (alternative):**
```bash
cd infra/terraform
terraform init
terraform plan -var-file="environments/dev.tfvars" \
  -var="db_admin_username=cloudadmin" \
  -var="db_admin_password=YourPassword123!"
terraform apply -var-file="environments/dev.tfvars" \
  -var="db_admin_username=cloudadmin" \
  -var="db_admin_password=YourPassword123!"

# Later...
terraform destroy -var-file="environments/dev.tfvars" \
  -var="db_admin_username=cloudadmin" \
  -var="db_admin_password=YourPassword123!"
```

---

## 2. Project Overview — The Elevator Pitch

> "I built a cloud-native microservices platform that deploys a 3-tier web application — React frontend, Node.js API, and PostgreSQL database — to Azure Kubernetes Service using exclusively Azure-native tooling. The infrastructure is fully codified with Terraform, configurations are managed with Kustomize across dev/staging/prod environments, and CI/CD runs through Azure DevOps Pipelines with gated approvals. The design emphasizes security (Key Vault secrets, RBAC, rate limiting, input validation), observability (Container Insights, metric alerts), and production readiness (HPA, PDB, rolling updates, health probes)."

**Key numbers to remember:**
- **49 files** across 6 directories
- **16 Azure resources** provisioned by Terraform
- **3 environments** (dev, staging, prod) with Kustomize overlays
- **3 CI/CD pipelines** (build, deploy, infrastructure)
- **0 third-party tools** — everything is Azure-native or built into kubectl

---

## 3. Architecture Decisions — Why This Design

### Why Azure-native services instead of third-party?

| Decision | What We Chose | What We Rejected | Why |
|----------|--------------|------------------|-----|
| Ingress | AKS Web App Routing | NGINX Ingress (community) | Zero extra pods, managed by Azure, auto-TLS |
| Secrets | Key Vault + CSI Driver | HashiCorp Vault | Native integration, RBAC-based, auto-rotation |
| Monitoring | Container Insights + Azure Monitor | Prometheus + Grafana | Zero infrastructure to manage, built into AKS |
| Config Mgmt | Kustomize | Helm | Built into kubectl, no templating engine, pure overlays |
| CI/CD | Azure DevOps Pipelines | Jenkins / GitHub Actions | Native Azure integration, artifact management |

**How to explain this in an interview:**
> "I intentionally chose Azure-native services to minimize operational overhead. Instead of running a Prometheus server, Grafana dashboard, and NGINX Ingress controller as additional pods in the cluster — which need their own monitoring, updates, and resource allocation — I leveraged managed versions that Azure maintains. This reduces the surface area I need to manage and lets me focus on application logic."

### Why Microservices Instead of a Monolith?

The API and frontend are separate services because:
1. **Independent deployment** — Update the API without redeploying the frontend
2. **Independent scaling** — The API can scale to 10 pods while the frontend stays at 3
3. **Technology isolation** — Node.js backend, Nginx frontend, each optimized for their purpose
4. **Failure isolation** — If the API crashes, the frontend still serves cached content

---

## 4. The Three Tiers Explained

### Tier 1: Frontend (React + Vite + Tailwind CSS + Nginx)

**What it does:**
- Serves a dark-themed dashboard with stat cards, product table, create/delete functionality
- Polls `/health` every 30 seconds to show live API/DB status
- Nginx reverse-proxies `/api/*` requests to the backend (no CORS issues in production)

**Key files:**
- `frontend/src/App.jsx` — Single-page React app with `useState`, `useEffect`, `fetch` calls
- `frontend/nginx.conf` — Proxy configuration: `/api` → `api:3001`, `/health` → `api:3001`
- `frontend/Dockerfile` — Two-stage build: Node builds the Vite bundle → Nginx serves static files

**Interview talking points:**
- Multi-stage Docker build reduces image size from ~1GB (node) to ~25MB (nginx:alpine + static files)
- Nginx handles SPA routing (all non-API routes return `index.html`)
- The health polling shows real-time system status without manual refresh

### Tier 2: API (Node.js + Express)

**What it does:**
- RESTful API with full CRUD on a `products` resource
- Health probes for Kubernetes (liveness, readiness, general health)
- Prometheus metrics endpoint for monitoring
- Security middleware stack: Helmet, CORS, rate limiting, input validation

**Key files:**
- `api/src/server.js` — Express app setup, middleware chain, route mounting
- `api/src/db.js` — PostgreSQL connection pool (max 20), table creation, seeding, slow query logging
- `api/src/routes/products.js` — Parameterized SQL queries, express-validator sanitization
- `api/src/routes/health.js` — 3 probe endpoints: `/health`, `/health/live`, `/health/ready`

**Interview talking points:**
- The readiness probe (`/health/ready`) checks DB connectivity — Kubernetes stops sending traffic if the DB is down
- The liveness probe (`/health/live`) is intentionally simple — if the process is alive, it's live
- Rate limiting at 100 requests/15 min prevents abuse
- Parameterized queries prevent SQL injection: `WHERE id = $1` not `WHERE id = ${id}`
- The connection pool (max 20) prevents connection exhaustion under load

### Tier 3: Database (PostgreSQL 16)

**What it does:**
- Stores the `products` table with auto-incrementing IDs, price validation, timestamps
- Locally: runs as a Docker container with a volume for persistence
- In Azure: runs as PostgreSQL Flexible Server (managed, SSL-enforced, backed up daily)

**Interview talking points:**
- Docker volume (`pgdata`) means data survives container restarts
- `CHECK (price >= 0)` constraint enforced at the database level, not just the API
- In Azure, geo-redundant backups are enabled for production
- The `AllowAzureServices` firewall rule allows only AKS → PostgreSQL traffic

---

## 5. Docker & Containerization — What You Built

### API Dockerfile (Multi-Stage)

```
Stage 1 (builder):  node:20-alpine → npm ci → produces node_modules
Stage 2 (runtime):  node:20-alpine → adduser nodejs (non-root) → copies node_modules + src
```

**Why multi-stage?**
- Build tools (npm, gcc for native modules) don't end up in the final image
- Final image is ~80MB instead of ~300MB
- Smaller image = faster pulls in Kubernetes = faster scaling

**Security details you should mention:**
- Runs as non-root user `nodejs` (UID 1001) — if the container is compromised, the attacker has minimal permissions
- Uses `npm ci` (clean install) not `npm install` — guarantees reproducible builds from lock file
- `.dockerignore` excludes `node_modules`, `.git`, tests — keeps the build context small

### Frontend Dockerfile (Multi-Stage)

```
Stage 1 (builder):  node:20-alpine → npm ci → npm run build → produces /app/dist (static files)
Stage 2 (runtime):  nginx:1.25-alpine → copies dist/ to nginx html dir → copies nginx.conf
```

**Why this is smart:**
- The final image is literally `nginx:alpine` + a few MB of static HTML/JS/CSS
- No Node.js runtime in production at all — Nginx serves pre-built files
- HEALTHCHECK directive lets Docker track if Nginx is responding

### Docker Compose

Three services on a bridge network:
1. `db` — PostgreSQL 16 (alpine), health check via `pg_isready`, volume for data persistence
2. `api` — Built from `./api/Dockerfile`, depends on db being healthy, exposes port 3001
3. `frontend` — Built from `./frontend/Dockerfile`, depends on api, exposes port 8080

**The `depends_on` with `condition: service_healthy` is important** — the API waits for PostgreSQL to actually accept connections, not just for the container to start.

---

## 6. Kubernetes — How It Runs in Production

### Deployments

Each service has a Deployment with:
- **Rolling update strategy** — `maxUnavailable: 0, maxSurge: 1` means zero downtime during updates (always at least N pods running, creates 1 extra during rollout)
- **Resource requests and limits** — tells the scheduler how much CPU/memory to reserve
- **Liveness probe** — Kubernetes restarts the pod if `/health/live` fails (the process is stuck)
- **Readiness probe** — Kubernetes stops routing traffic if `/health/ready` fails (DB is down)

### Services

ClusterIP services for internal communication:
- `api` → port 3001 (only reachable inside the cluster)
- `frontend` → port 80 (only reachable inside the cluster)

The Ingress resource exposes them externally.

### Secrets Management

The `SecretProviderClass` resource tells the Key Vault CSI Driver:
- Connect to Key Vault named `kv-cloudplatform-{env}`
- Mount secrets `db-password`, `db-host`, and `db-user` as files/env vars in the pod
- Auto-rotate every 2 minutes (configured on the AKS addon)

---

## 7. Kustomize — Why Not Helm?

### What Kustomize Does

Kustomize uses a **base + overlays** pattern:
- `k8s/base/` contains the canonical manifests (7 files)
- `k8s/overlays/dev/` patches the base for dev (1 replica, less CPU/memory)
- `k8s/overlays/staging/` patches for staging (2 replicas, moderate resources)
- `k8s/overlays/prod/` patches for prod (3 replicas, HPA, PDB, high resources)

### Why Kustomize Over Helm?

| Aspect | Kustomize | Helm |
|--------|-----------|------|
| Installed by default | Yes (built into kubectl) | No (separate binary) |
| Syntax | Pure YAML patches | Go templates ({{ .Values }}) |
| Learning curve | Low | High (templating logic) |
| Debugging | `kubectl kustomize .` shows final YAML | `helm template` + debug flags |
| Third-party | No — it's part of kubectl | Yes — separate project |

**Interview answer:**
> "I chose Kustomize because the project mandate was Azure-native with no third-party tools. Kustomize is built into kubectl, so there's no extra installation. It uses a declarative overlay system — the base manifests are valid YAML that you can apply directly, and each environment just patches the differences. With Helm, I'd need to learn Go templating and maintain a Chart.yaml, values.yaml, and templates directory. For this project's scale, that's unnecessary complexity."

---

## 8. Azure-Native Services — Every Service Justified

### AKS (Azure Kubernetes Service)

**What it provides:** Managed Kubernetes control plane — Azure handles etcd, API server, scheduler, controller manager. You only pay for worker nodes.

**Addons enabled in this project:**
1. **Web App Routing** — Managed NGINX Ingress controller. Azure deploys and updates it. You just create Ingress resources.
2. **Key Vault Secrets Provider** — CSI driver that mounts Key Vault secrets as files/env vars in pods. Auto-rotates every 2 minutes.
3. **OMS Agent (Container Insights)** — Ships pod/node metrics and logs to Log Analytics workspace.

**Configuration highlights:**
- Azure CNI networking (pods get real VNet IPs, not overlay)
- Azure network policy (Calico alternative, managed by Azure)
- System-assigned managed identity (no service principal credentials to manage)
- Azure RBAC for Kubernetes (users authenticate via Entra ID)
- Autoscaler: 2-5 nodes (dev), 3-10 nodes (prod)

### ACR (Azure Container Registry)

**What it provides:** Private Docker registry. AKS pulls images using its managed identity (AcrPull role). No `docker login` needed at runtime.

**Why not Docker Hub?** Private by default. No rate limits. Image scanning. Geo-replication (Premium SKU). Native RBAC.

### Azure Key Vault

**What it provides:** Centralized secrets management. Stores DB credentials securely. AKS pods access secrets via CSI volume mounts.

**RBAC mode** (not access policies) — permissions are managed through Azure RBAC roles:
- `Key Vault Secrets User` → AKS CSI driver (read secrets)
- `Key Vault Administrator` → Terraform deployer (create secrets)

### Azure PostgreSQL Flexible Server

**What it provides:** Managed PostgreSQL 16 with automatic backups, SSL enforcement, monitoring.

**Per-environment differences:**
- Dev: B_Standard_B1ms (burstable, cheap), 32GB storage, 7-day backups
- Prod: D_Standard_D2s_v3 (dedicated), 128GB, 35-day backups, geo-redundant, availability zone 1

### Azure Monitor + Container Insights

**What it provides:** Zero-config monitoring for AKS. Automatically collects:
- Node CPU/memory/disk usage
- Pod CPU/memory/restart counts
- Container logs (stdout/stderr)
- Kubernetes events

Two metric alerts are configured:
- **CPU > 80%** for 15 minutes → fires severity 2 alert
- **Memory > 80%** for 15 minutes → fires severity 2 alert

---

## 9. Terraform — Infrastructure as Code Explained

### Why Terraform?

- **Declarative** — You describe the desired state, Terraform figures out the changes
- **State tracking** — Terraform knows what exists, so it only modifies what changed
- **Plan before apply** — `terraform plan` shows exactly what will be created/destroyed
- **Multi-environment** — Same code, different `.tfvars` files per environment

### File Structure

| File | Purpose |
|------|---------|
| `provider.tf` | Azure provider v4.0, feature flags (purge protection, resource group deletion) |
| `variables.tf` | 11 variables with types, defaults, and validation rules |
| `main.tf` | 16 resources: RG, ACR, AKS, Key Vault, PostgreSQL, Monitor |
| `outputs.tf` | 11 outputs: names, FQDNs, connection strings |
| `environments/*.tfvars` | Per-environment variable values |

### Key Terraform Patterns Used

**1. Dynamic naming with locals:**
```hcl
locals {
  name_prefix = "${var.project_name}-${var.environment}"   # e.g., "cloudplatform-dev"
}
resource "azurerm_resource_group" "main" {
  name = "rg-${local.name_prefix}"                          # → "rg-cloudplatform-dev"
}
```

**2. Environment-conditional settings:**
```hcl
sku = var.environment == "prod" ? "Premium" : "Basic"       # ACR: Premium only in prod
zones = var.environment == "prod" ? [1, 2, 3] : []          # AKS: multi-AZ only in prod
```

**3. Sensitive variables:**
```hcl
variable "db_admin_password" {
  type      = string
  sensitive = true       # Terraform won't print this in logs or plan output
}
```

**4. Dependency management:**
```hcl
resource "azurerm_key_vault_secret" "db_password" {
  depends_on = [azurerm_role_assignment.deployer_kv_admin]   # Can't write secrets until we have admin access
}
```

**5. Remote state (production pattern):**
```hcl
backend "azurerm" {
  resource_group_name  = "tfstate-rg"
  storage_account_name = "tfstatecloudplatformdev"
  container_name       = "tfstate"
  key                  = "dev.tfstate"
}
```

### Interview answer — "Walk me through your Terraform":
> "It provisions 16 Azure resources. Starting with a resource group, then ACR for container images, a Log Analytics workspace for monitoring, and the AKS cluster with three addons — Web App Routing for ingress, Key Vault Secrets Provider for secrets management, and OMS Agent for Container Insights. I set up RBAC roles so AKS can pull from ACR and read Key Vault secrets. Key Vault stores the database credentials that get mounted into pods via the CSI driver. PostgreSQL Flexible Server is the managed database with environment-specific sizing. Finally, Azure Monitor metric alerts fire if CPU or memory exceeds 80%. The whole thing is parameterized through tfvars files — same code deploys dev, staging, or prod with different sizing."

---

## 10. CI/CD Pipeline Design — From Code to Production

### Pipeline 1: CI (ci-pipeline.yaml)

Triggers on pull requests AND merges to `main`.

```
Build & Test ──► Build Docker Images ──► Security Scan
   │                    │                      │
   ├─ npm ci            ├─ docker build        ├─ Trivy scans
   ├─ npm test          ├─ docker push → ACR   │  both images
   └─ npm audit         └─ tags: build ID      └─ fails on HIGH/CRITICAL
```

### Pipeline 2: CD (cd-pipeline.yaml)

Triggers after CI succeeds on `main`.

```
Deploy Dev (auto) ──► Deploy Staging (manual approval) ──► Deploy Prod (manual approval)
      │                         │                                  │
      ├─ kustomize build        ├─ kustomize build                 ├─ kustomize build
      ├─ kubectl apply -k       ├─ kubectl apply -k                ├─ kubectl apply -k
      └─ k8s/overlays/dev       └─ k8s/overlays/staging            └─ k8s/overlays/prod
```

### Pipeline 3: Infrastructure (infra-pipeline.yaml)

Triggers on changes to `infra/terraform/**`.

```
Validate ──► Plan Dev ──► Apply Dev ──► Plan Prod ──► Apply Prod
   │              │            │             │             │
   ├─ fmt -check  ├─ plan      ├─ apply      ├─ plan      ├─ apply
   └─ validate    └─ publish   └─ (auto)     └─ publish   └─ (approval)
```

**Interview answer — "Explain your CI/CD pipeline":**
> "There are three pipelines. CI runs on every PR — it installs dependencies, runs tests, builds Docker images tagged with the build ID, pushes them to ACR, then runs Trivy security scans that fail the build on HIGH or CRITICAL CVEs. CD has three stages — dev deploys automatically, staging and prod require manual approvals. Each stage uses Kustomize overlays, so the same base manifests get environment-specific patches. The infrastructure pipeline validates Terraform formatting and syntax, then runs plan/apply for dev automatically and prod with approval."

---

## 11. Security — Defense in Depth

### Application Layer (API)
- **Helmet** — Sets 11 security headers (X-Content-Type-Options, X-Frame-Options, Strict-Transport-Security, etc.)
- **CORS** — Configured per environment (strict origin in prod)
- **Rate limiting** — 100 requests per 15 min per IP on `/api/*`
- **Input validation** — express-validator: trim, escape, length limits, type checking
- **Parameterized SQL** — `$1, $2` placeholders prevent SQL injection
- **JSON body limit** — 10kb max prevents payload-based DoS
- **Non-root container** — UID 1001, no writable filesystem

### Infrastructure Layer (Terraform/Azure)
- **Managed identity** — AKS uses system-assigned identity, no credentials stored
- **RBAC everywhere** — Key Vault uses RBAC mode, AKS uses Azure RBAC
- **Key Vault for secrets** — DB credentials never in K8s Secrets, environment variables, or code
- **CSI driver auto-rotation** — Secrets refresh every 2 minutes
- **ACR admin disabled** — Only managed identity can pull images
- **PostgreSQL SSL-only** — `sslmode=require` in connection string
- **Network policies** — Azure CNI network policy restricts pod-to-pod traffic
- **Purge protection** — Enabled in prod to prevent accidental Key Vault deletion

### Kubernetes Layer
- **Resource limits** — Prevents a single pod from consuming all node resources
- **Rolling updates** — `maxUnavailable: 0` ensures zero downtime
- **PDB in prod** — `minAvailable: 2` prevents all pods from being evicted simultaneously
- **Readiness probes** — Traffic only routes to healthy pods

---

## 12. Observability & Monitoring

### What's Being Monitored

```
Container Insights (OMS Agent)
├── Node metrics: CPU, memory, disk, network
├── Pod metrics: CPU, memory, restart count, phase
├── Container logs: stdout, stderr → Log Analytics
└── Kubernetes events: deployments, scaling, errors

Azure Monitor Metric Alerts
├── CPU > 80% for 15 min → Severity 2 alert
└── Memory > 80% for 15 min → Severity 2 alert

Application-Level (Prometheus)
├── Default Node.js metrics: event loop lag, GC duration, heap usage
└── HTTP request duration, count, status codes
```

### How to query logs (KQL)

```kql
// Find API errors in the last hour
ContainerLogV2
| where ContainerName == "api"
| where LogMessage contains "error"
| order by TimeGenerated desc
| take 50

// Pod restart count
KubePodInventory
| where Name startswith "api"
| summarize RestartCount=sum(RestartCount) by Name
```

---

## 13. Networking & Ingress — How Traffic Flows

### Local (Docker Compose)

```
Browser → http://localhost:8080 → Nginx (frontend container)
  ├── Static files (HTML/JS/CSS) → served directly
  ├── /api/* → proxy_pass http://api:3001
  └── /health → proxy_pass http://api:3001

API container → http://db:5432 → PostgreSQL container
```

Docker's bridge network resolves container names (`api`, `db`) as DNS hostnames.

### Azure (AKS with Web App Routing)

```
Internet → Azure Load Balancer → AKS Web App Routing (Managed NGINX)
  ├── / → frontend Service (ClusterIP:80) → frontend pods (Nginx)
  ├── /api/* → api Service (ClusterIP:3001) → api pods (Express)
  ├── /health → api Service
  └── /metrics → api Service

API pods → Azure PostgreSQL Flexible Server (private FQDN, SSL)
API pods → Key Vault (via CSI volume mount for secrets)
```

The Ingress resource defines path-based routing:
- `/api`, `/health`, `/metrics` → API service
- `/` (everything else) → Frontend service

---

## 14. Database Strategy

### Schema

```sql
CREATE TABLE products (
  id          SERIAL PRIMARY KEY,
  name        VARCHAR(255) NOT NULL,
  description TEXT,
  price       DECIMAL(10,2) NOT NULL CHECK (price >= 0),
  category    VARCHAR(100),
  in_stock    BOOLEAN DEFAULT true,
  created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Connection Management
- Pool size: 20 connections max
- Idle timeout: 30 seconds (releases unused connections)
- Connection timeout: 5 seconds (fails fast if DB is down)
- Slow query logging: warns if any query takes > 1 second

### Migration Strategy
- `db.js` runs `CREATE TABLE IF NOT EXISTS` on startup — idempotent
- Seeds 8 products only if the table is empty (safe for restarts)
- In production, you'd use a dedicated migration tool (Flyway, node-pg-migrate)

---

## 15. Production Readiness Checklist

| Category | What's Implemented | How |
|----------|--------------------|-----|
| High Availability | Multi-replica, multi-AZ (prod) | 3 replicas + AZ 1,2,3 |
| Auto-scaling | Horizontal Pod Autoscaler | 3-10 API pods, 3-8 frontend pods at 70% CPU |
| Pod Disruption Budget | Prevents full eviction | minAvailable: 2 for both services |
| Rolling Updates | Zero-downtime deploys | maxUnavailable: 0, maxSurge: 1 |
| Health Probes | Kubernetes self-healing | Liveness (restart), Readiness (stop traffic) |
| Secrets Management | No hardcoded secrets | Key Vault → CSI driver → pod volume mounts |
| Monitoring | Full observability | Container Insights + metric alerts |
| Security | Defense in depth | Helmet, rate limit, RBAC, network policy, non-root |
| Backup | Database protection | 35-day retention + geo-redundant (prod) |
| Resource Limits | Prevent noisy neighbors | CPU/memory requests and limits on all pods |

---

## 16. Interview Q&A — 25 Questions You Will Be Asked

### Architecture & Design

**Q1: "Walk me through the architecture of this project."**
> "It's a 3-tier microservices platform. The frontend is React served by Nginx, the backend is a Node.js Express API, and the database is PostgreSQL. Locally, Docker Compose orchestrates all three. In production, they run on AKS with path-based routing through the Web App Routing ingress addon. Docker images are stored in ACR with managed identity pull access. Secrets are in Key Vault, injected via the CSI driver. Monitoring is Container Insights with metric alerts. Everything is codified — Terraform for infrastructure, Kustomize for Kubernetes manifests, Azure DevOps for CI/CD."

**Q2: "Why did you choose AKS over App Service or Container Apps?"**
> "AKS gives full Kubernetes control — custom networking, pod disruption budgets, HPA, Kustomize overlays, secrets provider classes. App Service is simpler but can't do multi-container orchestration with this level of control. Container Apps is close but doesn't support Kustomize or CSI drivers natively. For a project demonstrating cloud-native patterns, AKS is the right choice."

**Q3: "Why not just use a monolith?"**
> "A monolith would work for this scale, but the goal was demonstrating microservices patterns — independent deployment, independent scaling, failure isolation, and technology-appropriate containers. In a real production system, the API could be split further (auth service, product service, etc.)."

**Q4: "What would you add for a real production deployment?"**
> "A custom domain with TLS certificates via the Web App Routing addon's cert-manager integration. A CDN (Azure Front Door) in front of the frontend. A WAF for DDoS protection. Database connection pooling with PgBouncer. Distributed tracing with Application Insights. Secret version pinning. GitOps with Flux instead of imperative kubectl apply."

### Docker & Containers

**Q5: "Why multi-stage Docker builds?"**
> "To minimize the final image size. Build tools like npm, gcc, and python (for native modules) are only needed during `npm ci`. The runtime image only needs Node.js and the production dependencies. This reduces the API image from ~300MB to ~80MB, which means faster image pulls in Kubernetes and smaller attack surface."

**Q6: "Why alpine-based images?"**
> "Alpine Linux is ~5MB compared to Debian's ~120MB. Smaller image size means faster pulls and less storage. The trade-off is that some packages need to be compiled from source, but for Node.js and Nginx, the official alpine variants work perfectly."

**Q7: "Why run as non-root in the container?"**
> "Principle of least privilege. If an attacker exploits a vulnerability in the application, they get the permissions of the `nodejs` user (UID 1001), not root. They can't install packages, modify system files, or escalate privileges. It's a security best practice listed in the CIS Docker Benchmark."

### Kubernetes

**Q8: "Explain the difference between liveness and readiness probes."**
> "Liveness tells Kubernetes if the process is alive. If it fails, Kubernetes restarts the pod. Our liveness probe is `/health/live` which just returns 200 — if the Express process is running, it's live. Readiness tells Kubernetes if the pod can serve traffic. If it fails, the pod is removed from the Service's endpoints. Our readiness probe is `/health/ready` which checks database connectivity. So if the DB goes down, pods stay running but stop receiving new requests."

**Q9: "What is a Pod Disruption Budget and why do you need it?"**
> "A PDB limits how many pods can be simultaneously unavailable. Our PDB says `minAvailable: 2`, which means during a node drain (for upgrades or scaling), Kubernetes must keep at least 2 API pods running. Without it, a cluster upgrade could evict all pods at once, causing downtime."

**Q10: "Explain Kustomize base and overlays."**
> "The base directory has the canonical Kubernetes manifests — the 'standard' configuration. Overlays patch the base for each environment. Dev uses 1 replica with 100m CPU. Prod uses 3 replicas with 250m CPU, adds an HPA for autoscaling, and a PDB for disruption protection. The command `kubectl apply -k k8s/overlays/prod` renders the final YAML by merging base + prod patches."

**Q11: "How does the HPA work?"**
> "The Horizontal Pod Autoscaler monitors CPU utilization. When average CPU exceeds 70% across all API pods, it adds pods — up to 10. When CPU drops, it removes pods — down to 3. It checks every 15 seconds by default. The VPA (Vertical Pod Autoscaler) is an alternative that adjusts CPU/memory limits instead of replica count."

### Azure Services

**Q12: "How does AKS pull images from ACR without a docker login?"**
> "AKS uses a managed identity. The Terraform code creates a role assignment that grants the AKS kubelet identity the `AcrPull` role on the ACR resource. When Kubernetes needs to pull an image, the kubelet authenticates to ACR using its managed identity token — no password, no docker-config secret, no expiring credentials."

**Q13: "How do secrets get from Key Vault into pods?"**
> "The AKS cluster has the Key Vault Secrets Provider addon enabled. I create a `SecretProviderClass` resource that specifies which Key Vault and which secrets to mount. When a pod starts, the CSI driver authenticates to Key Vault using AKS's managed identity, retrieves the secrets, and mounts them as files in the pod's filesystem. The addon is configured to re-check every 2 minutes, so if I rotate a secret in Key Vault, pods pick it up automatically."

**Q14: "Why RBAC mode for Key Vault instead of access policies?"**
> "Access policies are legacy — they're per-vault and don't integrate with Azure RBAC. RBAC mode uses Azure role assignments, which means I can use the same permission model for Key Vault as every other Azure resource. It also supports conditional access, PIM, and audit logging through Azure AD."

### Terraform

**Q15: "What's the difference between terraform plan and terraform apply?"**
> "Plan is a dry run — it shows what Terraform would create, modify, or destroy without making any changes. It compares the desired state in your `.tf` files with the actual state in the state file and shows the diff. Apply executes the plan. In CI/CD, we always run plan first, publish the plan as an artifact, then apply that exact plan to avoid drift between the review and execution."

**Q16: "How do you handle Terraform state?"**
> "Locally, state is in `terraform.tfstate`. In production, we use an Azure Storage backend — the state file is stored in a blob container. This enables team collaboration (everyone reads the same state), state locking (prevents concurrent applies), and encryption at rest. The setup script creates the storage account before initializing Terraform."

**Q17: "How do you handle secrets in Terraform?"**
> "Variables are marked as `sensitive = true`, which prevents Terraform from showing them in plan output or logs. The actual values are passed via environment variables (`TF_VAR_db_admin_password`), never committed to code. In CI/CD, they're stored as pipeline secret variables."

### CI/CD

**Q18: "Why three separate pipelines instead of one?"**
> "Separation of concerns and different trigger conditions. CI runs on every PR — fast feedback. CD runs only on merge to main — actual deployment. Infrastructure runs only when Terraform files change — you don't want to re-plan infrastructure on every app code change. Each pipeline has its own approval gates — infra changes need different reviewers than app deploys."

**Q19: "Why gated approvals for staging and prod?"**
> "To prevent untested code from reaching production. Dev deploys automatically for fast iteration. Staging requires a manual approval because it's the last validation before prod — someone reviews the deployment, runs smoke tests. Prod requires a separate approval, often from a lead or manager. This implements the four-eyes principle."

### Security

**Q20: "How do you prevent SQL injection?"**
> "Parameterized queries. Instead of string interpolation like `WHERE id = ${req.params.id}`, I use `WHERE id = $1` with the value passed as a separate parameter array. The pg library handles escaping. Additionally, express-validator sanitizes input before it reaches the query — trimming whitespace, escaping HTML, checking types and ranges."

**Q21: "What does Helmet do?"**
> "Helmet sets 11+ HTTP response headers that mitigate common web vulnerabilities. X-Content-Type-Options prevents MIME sniffing. X-Frame-Options prevents clickjacking. Strict-Transport-Security enforces HTTPS. Content-Security-Policy restricts what resources the browser can load. It's a one-line middleware that eliminates an entire class of attacks."

**Q22: "How do you handle a compromised container?"**
> "Multiple defensive layers. The container runs as non-root, so privilege escalation is harder. Network policies restrict lateral movement — the frontend can't talk to the database directly. Key Vault secrets auto-rotate, so stolen credentials expire quickly. Container Insights would show anomalous behavior (unexpected network calls, CPU spikes). In a real scenario, I'd also have Azure Defender for Containers scanning for runtime threats."

### Monitoring & Troubleshooting

**Q23: "A pod is CrashLoopBackOff. How do you diagnose it?"**
> "First, `kubectl describe pod <pod-name>` to see events — it will show the exit code and reason for the last crash. Then `kubectl logs <pod-name> --previous` to see logs from the crashed container. Common causes: the container can't connect to the database (check secrets and network policies), a missing environment variable, or an uncaught exception on startup. The exit code matters — 137 means OOMKilled (increase memory limits), 1 means application error."

**Q24: "How do you diagnose slow API responses?"**
> "Start with Container Insights — check if the pod's CPU is throttled (hitting limits). Then check the database — the `db.js` module logs any query taking over 1 second. In Azure, check the PostgreSQL server's metrics for high DTU usage or lock waits. At the application level, Prometheus metrics show request duration histograms. If it's intermittent, it could be the Node.js event loop being blocked — check the `nodejs_eventloop_lag_seconds` metric."

**Q25: "The frontend shows 'Failed to load products'. What do you check?"**
> "Work backwards. (1) Is the API running? `kubectl get pods` — check if API pods are Ready. (2) Is the API healthy? `curl <ingress-ip>/health` — if DB shows disconnected, the issue is database connectivity. (3) Is the ingress routing correctly? `kubectl describe ingress` — check the backend services match. (4) Is it a CORS issue? Check browser console for CORS errors — the API's CORS_ORIGIN env var might be misconfigured. (5) Is it DNS? Try the ClusterIP directly from another pod."

---

## 17. Troubleshooting Scenarios

### Scenario 1: Docker Compose — API won't start

```
Error: connect ECONNREFUSED 127.0.0.1:5432
```
**Cause:** The API is trying to connect to `localhost` instead of the `db` container.
**Fix:** Ensure `DB_HOST=db` in docker-compose.yml (matches the service name).

### Scenario 2: Terraform — "Error: creating AKS cluster"

```
Error: creating Managed Kubernetes Cluster: performing CreateOrUpdate: unexpected status 409
```
**Cause:** A cluster with the same name already exists or is in a failed state.
**Fix:** `az aks list -o table` to check. Either delete the old cluster or change the name prefix.

### Scenario 3: AKS — Pods stuck in Pending

```
Events:
  Warning  FailedScheduling  0/2 nodes available: 2 Insufficient cpu.
```
**Cause:** Resource requests exceed available node capacity.
**Fix:** Either reduce resource requests in the overlay, or increase `aks_max_node_count` to let the autoscaler add nodes.

### Scenario 4: Key Vault — "SecretNotFound"

```
Error: keyvault.BaseClient#GetSecret: Failure responding to request: StatusCode=404
```
**Cause:** The secret name in `SecretProviderClass` doesn't match what's in Key Vault.
**Fix:** Check `az keyvault secret list --vault-name kv-cloudplatform-dev -o table`.

### Scenario 5: ACR — "Unauthorized" pull error

```
Error: ErrImagePull: unauthorized: authentication required
```
**Cause:** The AKS identity doesn't have `AcrPull` on the ACR.
**Fix:** Verify the role assignment exists: `az role assignment list --scope <acr-id> -o table`.

---

## 18. What Recruiters & Hiring Managers See

### Skills Demonstrated

| Category | What This Project Proves |
|----------|------------------------|
| **Cloud Architecture** | Multi-tier design, managed services selection, environment strategy |
| **Kubernetes** | Deployments, Services, Ingress, Kustomize, HPA, PDB, probes, CSI |
| **Infrastructure as Code** | Terraform with modules, variables, state management, multi-env |
| **CI/CD** | Multi-stage pipelines, gated approvals, security scanning |
| **Docker** | Multi-stage builds, non-root, health checks, compose |
| **Security** | Secrets management, RBAC, rate limiting, input validation, SQL injection prevention |
| **Monitoring** | Container Insights, metric alerts, Prometheus metrics, health endpoints |
| **Backend Development** | REST API, middleware chain, connection pooling, error handling |
| **Frontend Development** | React with hooks, Tailwind CSS, real-time health polling |
| **Database** | Schema design, migrations, seeding, connection management |

### What Makes This Stand Out

1. **It actually runs** — Not just diagrams, actual working code
2. **Azure-native purity** — Shows understanding of managed services over "install everything ourselves"
3. **Three environments** — Not just dev, full staging and prod configurations
4. **Security baked in** — Not an afterthought; Helmet, Key Vault, RBAC, input validation from day one
5. **Observable** — Health probes, Prometheus metrics, Container Insights, alerting
6. **Production patterns** — HPA, PDB, rolling updates, resource limits, multi-AZ

