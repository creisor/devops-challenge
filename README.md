# :rocket: DevOps Challenge

:wave: Hello and welcome to the DevOps Challenge! https://github.com/moonpay/devops-challenge

We're excited to see what you can do! This take-home exercise is your time to **show off your technical skills and aptitude**. We want to understand how you think, how you solve problems, and how you apply DevOps principles to real-world scenarios.

This exercise uses a simple Next.js application, but our focus is on your DevOps expertise—working with Containers, CI/CD, and Infrastructure as Code (IaC).

> **Note:** For development setup, scripts, and project structure details, see [DEVELOPMENT.md](DEVELOPMENT.md).

## :dart: Goal

Deploy the provided Next.js application in a **production-ready** manner.

## :clipboard: Requirements

You should be comfortable with:
1.  **Docker**: Building and running containers.
2.  **CI/CD & IaC**: Tools like GitHub Actions, Terraform, etc.
3.  **Orchestration**: Kubernetes (GKE or local).
4.  **Git**: Version control.

## :wrench: Tasks

### Task 1: Containerize the Application :package:

1.  Write a `Dockerfile` to containerize the application. :whale:
    *   Ensure it follows best practices for a Next.js application.
2.  Build and run the container locally to verify it works. :hammer_and_wrench:

### Task 2: Deploy the Application :rocket:

1.  Deploy the application to **Kubernetes** (GKE or a local cluster such as kind, minikube, or Docker Desktop).
2.  Ensure the solution is **as close to production-ready as possible**. Consider aspects like:
    *   Security
    *   Scalability
    *   Reliability
3.  Demonstrate that the application is reachable and returns the _Latest Crypto Prices_. :globe_with_meridians:

## :hourglass_flowing_sand: Time & Expectations

This is a take-home exercise — complete it on your own time and submit when you're ready. We want to see your best work! Be prepared to walk us through your solution and decision-making during the interview.

## :robot: AI Usage

If you use AI tools to assist with this challenge, please bring the prompts you used to the interview. The interviewers would like to understand how you arrived at your solution.

Good luck! :four_leaf_clover:

---

## Solution Overview

### Containerization

The application is packaged using a three-stage `Dockerfile` (`node:22-alpine`):
- **deps** — installs production dependencies
- **builder** — installs all dependencies and runs `next build` with `output: 'standalone'`
- **runner** — minimal image containing only the standalone output; runs as non-root user (UID 1001)

### Kubernetes Deployment

The app is deployed to a local k3s cluster using two Helm charts:

| Chart | Path | Description |
|-------|------|-------------|
| App | `helm/app/` | Deployment, Service, Traefik Ingress, HPA (2–3 replicas), Prisma migration Job hook |
| Postgres | `helm/postgres/` | Bitnami postgresql chart, StatefulSet with `local-path` PVC |

Prisma migrations run automatically as a Helm `pre-install`/`pre-upgrade` hook before each deploy.

### CI/CD

GitHub Actions (`.github/workflows/deploy.yml`) runs on a **self-hosted runner** on the same LAN as the cluster. On every push to `main`:

1. Builds the Docker image
2. Scans with Trivy (fails on CRITICAL/HIGH CVEs)
3. Pushes to GitHub Container Registry (GHCR)
4. Deploys via `helm upgrade --install`
5. Runs a `curl`-based smoke test

### Local Access

The cluster is on a private LAN. Use the SSH tunnel script for local access:

```bash
export SSH_HOST=<k3s-host-ip>
./scripts/tunnel.sh
```

Then visit `http://devops-challenge.local:8080`. See [docs/ssh-tunnel.md](docs/ssh-tunnel.md) for full setup.

### Terraform

Terraform was evaluated and determined to be out of scope for this local k3s
environment. All infrastructure is managed through Helm charts.
