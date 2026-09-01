# Security Policy

This is a personal portfolio project, not a commercial product with a dedicated
security team. That said, it is built with real production practices in mind and
security is treated seriously within that scope.

## What this project does for security

- **Secrets management**: application secrets live in Azure Key Vault and are
  mounted into pods via the Key Vault CSI driver as volumes. They are never
  committed to the repo, baked into images, or stored in plain environment
  variables. Key Vault runs in RBAC mode with rotation enabled.
- **Containers**: images are built as multi-stage, non-root Docker builds on
  pinned base images, with HEALTHCHECK instructions and Dockerfiles linted by
  hadolint in CI.
- **CI security scanning**: Trivy scans both application images for CRITICAL and
  HIGH severity CVEs on every build, and Checkov scans the Terraform code for
  infrastructure misconfigurations. Both run on every push and PR. Findings are
  report-only, since base-image and third-party CVEs shift daily and are outside
  this application's direct control, but they are visible in the CI logs for
  every build.
- **Kubernetes manifests**: Kustomize overlays for dev, staging, and prod are
  validated in CI with kubeconform so malformed or invalid manifests fail the
  build before they can reach a cluster.
- **API hardening**: the Node API uses Helmet for security headers, per-IP rate
  limiting, express-validator for input validation, a 10 kb JSON body limit, and
  parameterized SQL queries throughout (no string-built queries).
- **Cluster access**: ACR pulls use managed identity rather than static
  credentials, and PostgreSQL connections are SSL-only.

## What this project does not do

There is no bug bounty, no paid incident response, and no guaranteed response
time. This is a solo-maintained repo. Dependency and base-image CVEs are
monitored via Trivy and Dependabot but not all findings are immediately
actioned, since many apply to a demo environment rather than a live production
system handling real user data.

## Reporting a vulnerability

If you find a security issue in this repository, please open a GitHub issue on
this repo describing the problem, or, if the issue is sensitive (for example a
leaked credential or something you would not want public before a fix), use
GitHub's private vulnerability reporting feature on this repository instead of
a public issue.

There is no formal SLA, but issues will be looked at and addressed as time
allows. Thank you for taking the time to report anything you find.
