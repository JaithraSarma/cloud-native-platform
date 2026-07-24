# Setup and Implementation Guide

This guide walks through running the platform locally, running the tests, using the
observability stack, and deploying to Azure. Each section states what to run and what
output to expect.

## Prerequisites

| Tool | Version | Needed for |
|---|---|---|
| Docker Desktop | current | Local run, image builds |
| Node.js | 20.x LTS | Running tests and lint outside containers |
| Git | current | Cloning the repository |
| Azure CLI | current | Azure deployment only |
| Terraform | >= 1.5 | Azure deployment only |
| kubectl | current | Azure deployment only |

For a local demo you only need Docker Desktop (and Node.js if you want to run the tests
directly). The Azure tools are required only for Section D.

Copy the example environment file before you start; real secrets go in `.env`, which is
git-ignored:

```bash
cp .env.example .env
```

---

## A. Run locally with Docker Compose

1. Build the images and start the stack:

   ```bash
   docker compose up --build -d
   ```

   The API waits for PostgreSQL to pass its health check before starting, then creates the
   `products` table and seeds eight rows on first boot.

2. Confirm all three services are healthy (allow ~30 seconds for health checks):

   ```bash
   docker compose ps
   ```

   Expected output:

   ```
   NAME                     SERVICE    STATUS                 PORTS
   cloudplatform-db         db         Up (healthy)           0.0.0.0:5432->5432/tcp
   cloudplatform-api        api        Up (healthy)           0.0.0.0:3001->3001/tcp
   cloudplatform-frontend   frontend   Up (healthy)           0.0.0.0:8080->80/tcp
   ```

3. Check the API health endpoint:

   ```bash
   curl http://localhost:3001/health
   ```

   Expected output:

   ```json
   {"status":"healthy","service":"cloud-platform-api","version":"1.0.0",
    "uptime":34.65,"database":"connected","hostname":"730fd41bcfe8",
    "memory":{"used":"12MB","total":"13MB"}}
   ```

4. List the seeded products:

   ```bash
   curl http://localhost:3001/api/products
   ```

   Expected output (truncated):

   ```json
   {"count":8,"products":[
     {"id":1,"name":"Kubernetes Cluster License","price":"2999.99",
      "category":"Infrastructure","in_stock":true, ...},
     ... 8 items ...
   ]}
   ```

5. Open the dashboard at **http://localhost:8080**. It shows the product table, stat cards,
   and a health indicator that polls `/health`. Requests to `/api` are proxied by Nginx to
   the API container, so there is no CORS configuration to manage.

6. Create a product to confirm writes work:

   ```bash
   curl -X POST http://localhost:3001/api/products \
     -H "Content-Type: application/json" \
     -d '{"name":"Test Product","price":9.99,"category":"Test"}'
   ```

   Expected: HTTP 201 with the created product (including its new `id`).

7. Stop the stack and remove volumes when finished:

   ```bash
   docker compose down -v
   ```

`make up`, `make ps`, and `make down` wrap these commands.

---

## B. Run the test suite

The API has 12 Jest tests using supertest. They mock the database, so no running
PostgreSQL is required.

```bash
cd api
npm ci
npm test
```

Expected output (tail):

```
Test Suites: 1 passed, 1 total
Tests:       12 passed, 12 total
Time:        ~7 s
```

Coverage is printed with the results (around 72% of lines). `npm run lint` runs ESLint over
`src/`. The frontend has `npm run lint` and `npm run build`. `make test` and `make lint`
run these for you.

---

## C. Observability stack (Prometheus + Grafana)

1. Start the monitoring profile in addition to the app:

   ```bash
   docker compose --profile monitoring up -d
   ```

   This adds Prometheus (port 9090) and Grafana (port 3000). Without the `--profile
   monitoring` flag, `docker compose up` starts only the three application services.

2. Confirm Prometheus is scraping the API. Open **http://localhost:9090/targets** or query:

   ```bash
   curl -s http://localhost:9090/api/v1/targets
   ```

   Expected: the `cloud-platform-api` target at `http://api:3001/metrics` shows health
   `up`:

   ```
   cloud-platform-api   http://api:3001/metrics       up
   prometheus           http://localhost:9090/metrics up
   ```

3. Open Grafana at **http://localhost:3000** and log in with `admin` / `admin` (local
   credentials only). Confirm it is serving:

   ```bash
   curl http://localhost:3000/api/health
   # {"database":"ok","version":"11.2.0"}
   ```

4. Open the pre-provisioned dashboard: **Dashboards → Cloud Platform → Cloud Platform API —
   Runtime**. Panels cover process CPU, resident memory, Node heap used vs total,
   event-loop lag, active handles, and API up/down.

5. Generate some load and watch the panels move:

   ```bash
   for i in $(seq 1 500); do curl -s http://localhost:3001/api/products > /dev/null; done
   ```

6. Tear down the monitoring stack:

   ```bash
   docker compose --profile monitoring down
   ```

`make monitoring-up` and `make monitoring-down` wrap steps 1 and 6.

---

## D. Deploy to Azure

This provisions real Azure resources and will incur cost. Run the teardown in Section D.5
when done.

### D.1 Authenticate

```bash
az login
az account set --subscription "<your-subscription-id>"
```

Provide the database credentials as environment variables so they never touch source
control:

```bash
export TF_VAR_db_admin_username="cloudadmin"
export TF_VAR_db_admin_password="<a strong password>"
```

### D.2 Provision with the setup script

```bash
chmod +x scripts/setup-azure.sh scripts/teardown.sh
./scripts/setup-azure.sh dev eastus2
```

The script creates a storage account for Terraform remote state, runs
`terraform init/plan/apply`, retrieves AKS credentials, builds and pushes both images to
ACR, and applies the dev Kustomize overlay.

### D.3 What Terraform creates

`infra/terraform/main.tf` provisions **18 resources**: a resource group, container
registry, Log Analytics workspace, AKS cluster (with Web App Routing, Key Vault secrets
provider, and Container Insights add-ons), the ACR pull and Key Vault role assignments,
the Key Vault, four Key Vault secrets, a PostgreSQL Flexible Server plus database and
firewall rule, an action group, and two metric alerts (CPU and memory > 80%).

Names follow the pattern `<type>-cp-<env>-6284`, for example `rg-cp-dev-6284`,
`aks-cp-dev-6284`, `kv-cp-dev-6284`, `psql-cp-dev-6284`, and ACR `acrcpdev6284`.

To run Terraform manually instead of the script:

```bash
cd infra/terraform
terraform init
terraform plan  -var-file="environments/dev.tfvars"
terraform apply -var-file="environments/dev.tfvars"
```

(`TF_VAR_db_admin_username` and `TF_VAR_db_admin_password` are read from the environment.)

### D.4 Verify the deployment

```bash
kubectl get pods -n cloud-platform-dev      # pods Running
kubectl get ingress -n cloud-platform-dev   # note the external IP
curl http://<EXTERNAL-IP>/health            # returns healthy
curl http://<EXTERNAL-IP>/api/products      # returns the seeded products
```

Namespaces are `cloud-platform-dev`, `cloud-platform-staging`, and `cloud-platform-prod`.
Replica counts are 1 (dev), 2 (staging), and 3 (prod); prod also applies a Horizontal Pod
Autoscaler and a Pod Disruption Budget.

### D.5 Tear down

```bash
./scripts/teardown.sh dev
# confirm when prompted — this destroys all Azure resources for the environment
```

---

## E. Troubleshooting

**`docker compose up` fails with "port is already allocated".**
Another process is using 8080, 3001, or 5432. Stop it, or change the host port mapping in
`docker-compose.yml` (left side of `host:container`).

**API container is unhealthy or restarts.**
Check `docker compose logs api`. The most common cause is the database not being ready; the
API exits if it cannot initialize the schema. `docker compose ps` should show `db` as
`(healthy)` before the API starts.

**`terraform apply` fails creating the AKS cluster with a 409 conflict.**
A cluster with the same name already exists or is in a failed state. Run `az aks list -o
table`, then delete the stale cluster or change the environment suffix.

**Pods fail to pull images with "unauthorized".**
The AKS managed identity is missing the `AcrPull` role on the registry. Confirm the role
assignment exists: `az role assignment list --scope <acr-id> -o table`.

**Grafana shows no data.**
Confirm the Prometheus target is `up` (Section C.2) and that the application stack is
running — the monitoring profile scrapes `api:3001`, which must be on the same Compose
network.

---

## Cost note

When using Azure free or student credits, always run `scripts/teardown.sh` after a demo.
AKS, PostgreSQL Flexible Server, and a Premium ACR (prod) accrue cost while running.
