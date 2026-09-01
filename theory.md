# Cloud-Native Platform: Study Booklet

This document explains the entire project end to end so you can present it in an
interview and answer follow-up questions with confidence. It covers what the system is,
why each piece exists, how the pieces fit together, and how the same design maps across
Azure, AWS, and GCP. Read it top to bottom once, then use the interview questions at the
end to rehearse.

---

## 1. The one-paragraph summary

This is a three-tier web application (React frontend, Node.js/Express API, PostgreSQL
database) plus the full platform used to build, ship, and run it: Docker images,
Kubernetes manifests managed with Kustomize, Terraform for cloud infrastructure, and a
GitHub Actions pipeline that lints, tests, scans, validates, and publishes. The
application itself is deliberately small (a products catalog with CRUD) because the point
of the project is the platform and the operational practices around the app, not the
business logic. Azure is the fully built and verified target. AWS is implemented in
infrastructure-as-code to the same shape. GCP is documented as an equivalence mapping.

If someone asks "what is this project," say: "It is a production-grade deployment platform
for a small web service. It shows the path from a git push to a running, observable,
secured workload on a managed Kubernetes cluster, with the same architecture expressed
for more than one cloud."

---

## 2. Why it is built this way (the guiding ideas)

1. **The app is a vehicle, the platform is the subject.** A products CRUD service keeps the
   business logic trivial so the interesting work is delivery, security, and operations.
2. **Everything is reproducible.** Lockfiles are committed, images are multi-stage and
   pinned, infrastructure is declared in Terraform, and Kubernetes state is declarative
   Kustomize. Nothing is created by hand that is not also written down.
3. **Security is built in, not bolted on.** Non-root containers, read-only root
   filesystems, dropped Linux capabilities, secrets from a managed vault, network
   policies, and image and IaC scanning in CI.
4. **Honesty over theater.** Scanners that flag issues outside the app's control (daily
   base-image CVEs) are report-only so the build badge reflects real application health.
   The AWS side is labeled as IaC-complete rather than claimed as deployed, because it has
   not been run against a live account.

---

## 3. The three tiers

### 3.1 Frontend

- React 18 built with Vite 5 and styled with Tailwind CSS 3.
- Served in production by Nginx. The image is `nginxinc/nginx-unprivileged`, which runs as
  a non-root user (uid 101) and listens on port 8080 rather than 80. This matters because
  a container that runs as root is the single most common thing a reviewer flags on a
  "production-grade" claim.
- Nginx also reverse-proxies `/api` and `/health` to the API container, so in the browser
  there is a single origin and no CORS to manage.
- A Vitest render test asserts the dashboard mounts and shows its heading. It runs in CI.

### 3.2 API

- Node.js 20 with Express 4.
- Security middleware: Helmet (HTTP security headers), a per-IP rate limiter on `/api`,
  `express-validator` on every write, a 10 kb JSON body limit, and parameterized SQL
  everywhere (values are passed as query parameters, never string-concatenated, which is
  what prevents SQL injection).
- Observability: `prom-client` exposes Prometheus metrics at `/metrics`, and logging is
  structured JSON via `pino`/`pino-http` with a per-request correlation id. Structured
  logs are machine-parseable, which is what a real log aggregator needs.
- Health endpoints: `/health` (full status including a database check), `/health/live`
  (liveness, is the process up), and `/health/ready` (readiness, can it serve traffic,
  which fails if the database is unreachable).
- Graceful shutdown: on `SIGTERM` or `SIGINT` the server stops accepting new connections,
  drains the PostgreSQL connection pool, then exits, with a bounded timeout that forces
  exit if draining hangs. This is what lets Kubernetes roll pods without dropping
  in-flight requests.
- API contract: an OpenAPI 3.0 document lives at `api/openapi.yaml` and is served at
  `/openapi.yaml`. It describes every endpoint, the request and response schemas, and the
  status codes the code actually returns.

### 3.3 Database

- PostgreSQL 16. Locally it runs as a container. In the cloud it is a managed service
  (Azure Database for PostgreSQL Flexible Server, or Amazon RDS for PostgreSQL).
- The API creates the `products` table on first boot and seeds eight rows if the table is
  empty. Connections use TLS in the cloud.

---

## 4. Containers

- Both images use multi-stage builds: a builder stage installs dependencies or builds the
  bundle, and a smaller runtime stage copies only what is needed. This keeps the final
  image small and free of build tooling.
- Both run as non-root, on pinned Alpine base images, with a `HEALTHCHECK`.
- The API health check hits `127.0.0.1` rather than `localhost` to avoid an IPv6
  resolution quirk that made the check flap.
- Dockerfiles are linted by hadolint in CI, and images are scanned by Trivy.

---

## 5. Local development: Docker Compose

- `docker compose up --build -d` starts three services on one bridge network: `db`, `api`,
  `frontend`. The API waits for the database health check before it starts.
- An opt-in monitoring profile (`docker compose --profile monitoring up -d`) adds
  Prometheus and Grafana, pre-provisioned to scrape the API and load a runtime dashboard.
- Credentials in Compose are local-only defaults expressed as `${VAR:-default}`, so nothing
  secret is hardcoded and any value can be overridden from a git-ignored `.env`.

---

## 6. Kubernetes

The manifests live in `k8s/` and are organized with Kustomize.

### 6.1 Base resources

- Deployments for `api` and `frontend`, their Services, an Ingress, a dedicated
  ServiceAccount, NetworkPolicies, and a SecretProviderClass for mounting secrets.
- **Probes.** Liveness (restart if the process wedges), readiness (remove from the load
  balancer if it cannot serve), and a startup probe (give a slow first boot time before
  liveness kicks in).
- **Rolling updates** with `maxUnavailable: 0` and `maxSurge: 1`, so a deploy brings up a
  new pod before removing an old one and never drops below the desired count.
- **securityContext** on both pods and containers: `runAsNonRoot`, a specific non-root
  uid, `readOnlyRootFilesystem: true`, all Linux capabilities dropped, and the
  `RuntimeDefault` seccomp profile. Because the root filesystem is read-only, the pods get
  small `emptyDir` volumes for the paths that must be writable (a temp dir for the API, and
  Nginx cache and run directories for the frontend).
- **ServiceAccount hardening**: a dedicated ServiceAccount with
  `automountServiceAccountToken: false`, because neither container talks to the Kubernetes
  API and an unused token is attack surface.
- **NetworkPolicy**: default-deny ingress, then explicit allows for exactly the traffic the
  app needs (ingress controller to frontend, frontend to API, API egress to DNS and to
  PostgreSQL). This is meaningful because the AKS cluster enables the Azure network policy
  engine, so these policies are actually enforced.
- **Graceful draining**: the API deployment sets `terminationGracePeriodSeconds` and a
  `preStop` hook that sleeps briefly, so the load balancer deregisters the pod before the
  process receives SIGTERM. This pairs with the application-level graceful shutdown.

### 6.2 Overlays

- Environment overlays under `k8s/overlays/`: dev (1 replica), staging (2), and prod (3,
  plus a HorizontalPodAutoscaler and a PodDisruptionBudget). Overlays patch replica counts
  and resource requests and limits, and set the image registry and tag.
- A cloud overlay under `k8s/aws/` takes the same base and swaps the cloud-specific pieces:
  the Ingress becomes an AWS Load Balancer Controller (ALB) ingress, the SecretProviderClass
  switches to the AWS provider reading from Secrets Manager, and the ServiceAccount is
  annotated for IRSA (IAM Roles for Service Accounts). This shows how one base ports across
  clouds by changing only the edges.

### 6.3 Secrets on Kubernetes

- Secrets are never in manifests or images. They live in a managed vault and are mounted
  into the pod as files by the Secrets Store CSI driver, which then syncs them into a
  Kubernetes Secret that the Deployments read as environment variables.
- On Azure the provider is Azure Key Vault. On AWS it is Secrets Manager, and the pod's
  ServiceAccount is granted access through IRSA rather than a static credential.

---

## 7. Infrastructure as Code: Terraform

### 7.1 Azure (built and verified) at `infra/terraform/`

Provisions roughly eighteen resources: a resource group, Azure Container Registry, a Log
Analytics workspace, an AKS cluster (with the Web App Routing ingress add-on, the Key
Vault secrets provider, and Container Insights), the role assignments that let AKS pull
from ACR and read Key Vault, the Key Vault and its secrets, a PostgreSQL Flexible Server
with a database and firewall rule, and an action group with two metric alerts (CPU and
memory above 80 percent). Environment differences (SKUs, replica of protections,
availability zones, backup retention) are driven by the `environment` variable.

### 7.2 AWS (IaC-complete, validated) at `infra/terraform/aws/`

Mirrors the Azure shape with AWS-native services: a VPC with public and private subnets
across two availability zones and a cost-conscious single NAT gateway, ECR repositories,
an EKS cluster and managed node group with the OIDC provider enabled for IRSA, an RDS
PostgreSQL instance (encrypted, private, security-group-scoped to the nodes), four Secrets
Manager secrets, an IAM role and policy for IRSA that lets the app ServiceAccount read
those secrets, and a CloudWatch log group with two alarms. It passes `terraform validate`
and `terraform fmt`. It has not been applied to a live account, so treat it as
deploy-ready rather than deployed.

### 7.3 State and reproducibility

Both configurations pin the Terraform version and the provider version, and include a
commented remote-backend block (Azure Storage for Azure, S3 with DynamoDB locking for AWS).
Remote state with locking is what stops two people from corrupting state with concurrent
applies.

---

## 8. CI/CD: GitHub Actions

### 8.1 The CI workflow (`.github/workflows/ci.yml`)

Runs on every push and pull request to `main`, with a `concurrency` group that cancels a
superseded run on the same ref. Jobs:

- `api-tests`: install with `npm ci`, ESLint, Jest, and a non-blocking `npm audit`.
- `frontend-build`: install, ESLint, the Vitest test, and a Vite build.
- `docker-and-scan`: build both images and scan them with Trivy (report-only, because
  unfixed base-image CVEs are outside the app's control).
- `hadolint`: lint both Dockerfiles.
- `terraform-checks`: a matrix over the Azure and AWS configs running `fmt -check`,
  `init -backend=false`, and `validate`.
- `k8s-validate`: build every Kustomize overlay (the env overlays and the AWS overlay) and
  validate the output with kubeconform. This one is a hard gate, because the manifests are
  the app's own YAML and within its control.
- `iac-scan`: Checkov over the Terraform (report-only, same rationale as Trivy).

### 8.2 The release workflow (`.github/workflows/release.yml`)

On a push to `main` or a `v*.*.*` tag, a matrix job builds both images and publishes them
to GitHub Container Registry. Tagging is derived automatically: a commit-sha tag and
`edge` and `latest` on main, and semantic-version tags on a release tag. Each image is
published with an SBOM (software bill of materials) and build provenance attestation, which
are the supply-chain artifacts a security-minded reviewer looks for. It authenticates with
the built-in `GITHUB_TOKEN`, so no cloud secrets are needed, and its permissions are
least-privilege (`contents: read`, `packages: write`).

### 8.3 Why not a deploy-to-cluster job

Deploying to AKS or EKS needs live cloud credentials, which this repository does not carry.
The `pipelines/` directory holds an Azure DevOps pipeline set (CI, gated CD, and infra) as
a reference for what an Azure-native, credentialed deploy path looks like.

---

## 9. Observability

- **Metrics** come from `prom-client` at `/metrics`. Locally, the monitoring profile runs
  Prometheus and Grafana with a pre-provisioned dashboard covering CPU, memory, Node heap,
  event-loop lag, and up/down.
- **In-cluster on Azure**, Container Insights ships logs and metrics to Log Analytics, and
  Azure Monitor raises the CPU and memory alerts. On AWS the equivalent is Container
  Insights feeding CloudWatch, with CloudWatch alarms.
- **Logs** are structured JSON with a request id, so a single request can be traced across
  log lines.

---

## 10. Cross-cloud mapping (know this cold)

The application, the container images, the Kubernetes base manifests, and the image
publishing are all cloud-neutral. Only the managed infrastructure and the cloud edges
differ. This table is the heart of the multi-cloud story.

| Concern | Azure (built) | AWS (IaC-complete) | GCP (documented) |
|---|---|---|---|
| Managed Kubernetes | AKS | EKS | GKE |
| Container registry | ACR | ECR | Artifact Registry |
| Managed PostgreSQL | PostgreSQL Flexible Server | RDS for PostgreSQL | Cloud SQL for PostgreSQL |
| Secrets store | Key Vault | Secrets Manager | Secret Manager |
| Pod-to-secret identity | Key Vault CSI + managed identity | Secrets Store CSI + IRSA | Secret Manager CSI + Workload Identity |
| Ingress | Web App Routing (managed NGINX) | AWS Load Balancer Controller (ALB) | GKE Ingress / Gateway |
| Registry pull auth | Managed identity AcrPull | Node IAM role (ECR read) | Workload Identity / node SA |
| Logs and metrics | Container Insights + Log Analytics | Container Insights + CloudWatch | Cloud Logging + Cloud Monitoring |
| Alerting | Azure Monitor metric alerts | CloudWatch alarms | Cloud Monitoring alerting policies |
| Terraform provider | `azurerm` | `aws` | `google` |

The key sentence to say: "The workload is identical everywhere. What changes per cloud is
the managed service behind each capability and the mechanism that gives a pod a cloud
identity: managed identity on Azure, IRSA on AWS, Workload Identity on GCP."

---

## 11. Security posture, in one place

- Application: security headers, rate limiting, input validation, parameterized SQL, small
  body limit, structured logs without secrets.
- Containers: non-root, read-only root filesystem, dropped capabilities, seccomp, pinned
  bases, health checks, Trivy and hadolint in CI.
- Kubernetes: default-deny NetworkPolicy, ServiceAccount token not mounted, secrets from a
  vault via CSI, not from manifests.
- Cloud: secrets in a managed vault, pod identity through the cloud-native mechanism rather
  than static keys, private database not publicly reachable, TLS to the database.
- Supply chain: SBOM and provenance on published images, Checkov on Terraform, Dependabot
  for weekly dependency updates.

---

## 12. Design decisions and tradeoffs (be ready to defend these)

- **Report-only scanning for base-image and IaC findings.** A hard gate on CVEs that change
  daily and are not the application's fault would keep the badge red for no useful reason.
  The findings are still printed in the build log. The manifests, which are the app's own
  code, are hard-gated.
- **Single NAT gateway on AWS.** Two NAT gateways give per-AZ resilience but double the
  hourly cost. For a portfolio and non-production environment a single NAT is the right
  cost tradeoff, and it is called out in the code.
- **Non-root Nginx via the unprivileged image.** Rather than patch a root Nginx, the
  project uses the image that is designed to run unprivileged, which is the clean way to
  get a read-only root filesystem to work.
- **Kustomize over Helm.** For a project with a handful of environments and a small set of
  resources, Kustomize overlays are simpler and need no templating language. Helm earns its
  complexity when you publish a reusable chart, which is not the goal here.
- **Azure fully built, AWS as IaC, GCP documented.** This shows depth on one cloud with a
  verified running system, breadth on a second through real infrastructure code, and fluency
  on the third, without pretending to have deployed three times.

---

## 13. Likely interview questions and strong answers

- **How does a request flow through the system?** Browser hits the ingress, which routes to
  the frontend Nginx for the UI and proxies `/api` and `/health` to the API service. The
  API validates input, runs a parameterized query against PostgreSQL, and returns JSON. The
  pod reads database credentials from a Secret that the CSI driver populated from the cloud
  vault.
- **How do you deploy without downtime?** Rolling update with `maxUnavailable: 0`, readiness
  probes so traffic only goes to pods that can serve, a preStop hook plus a termination
  grace period so the load balancer deregisters a pod first, and application-level graceful
  shutdown that drains the connection pool before exit.
- **How are secrets handled?** They never touch the repo or the image. They live in Key
  Vault or Secrets Manager and are mounted by the Secrets Store CSI driver. The pod proves
  its identity to the cloud through managed identity on Azure or IRSA on AWS, so there is no
  long-lived credential to leak.
- **What stops SQL injection?** Every query uses parameter placeholders and passes values
  separately, so user input is never interpolated into SQL text. Inputs are also validated
  and length-limited before they reach the query.
- **Why are some scans non-blocking?** Because they report on things outside the
  application's control, like OS packages in a base image, which change daily. Gating on
  them would produce noise, not signal. The app's own artifacts, the Kubernetes manifests,
  are hard-gated.
- **How would you take this to production for real?** Add a credentialed deploy job that
  applies Terraform and rolls the Kustomize overlay, enable remote Terraform state with
  locking, wire the alerts to a real notification channel, and put an in-cluster metrics
  pipeline behind the NetworkPolicy allowances.
- **How is this multi-cloud?** The workload and manifests are cloud-neutral. Only the
  managed services and the pod-identity mechanism differ. Point at the mapping table and the
  `k8s/aws` overlay as evidence.
- **What is IRSA and why use it?** IAM Roles for Service Accounts binds a Kubernetes
  ServiceAccount to an IAM role through the cluster's OIDC provider, so a pod gets scoped
  AWS permissions with no static keys. Here it lets the app ServiceAccount read exactly the
  four database secrets and nothing else.

---

## 14. Glossary

- **Kustomize overlay**: a layer that patches a shared base set of manifests for a specific
  environment or cloud, without copying the base.
- **Probe (liveness/readiness/startup)**: Kubernetes health checks that decide whether to
  restart a pod, send it traffic, or wait for it to finish starting.
- **securityContext**: pod and container settings that constrain privileges (user, root
  filesystem, capabilities, seccomp).
- **NetworkPolicy**: a firewall for pod-to-pod and pod-to-external traffic inside the
  cluster.
- **CSI driver**: Container Storage Interface plugin; here the Secrets Store CSI driver
  mounts vault secrets as files.
- **IRSA / managed identity / Workload Identity**: the AWS, Azure, and GCP mechanisms for
  giving a pod a cloud identity without static credentials.
- **SBOM**: software bill of materials, a machine-readable inventory of what is in an image.
- **Provenance attestation**: signed metadata about how and where an image was built.
- **HPA / PDB**: HorizontalPodAutoscaler scales replicas on load; PodDisruptionBudget limits
  how many pods can be voluntarily taken down at once.
