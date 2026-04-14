# Self-Hosted GitHub Actions Runner

The CI/CD pipeline deploys to a local k3s cluster that is not reachable from
GitHub's hosted runners. A self-hosted runner on the same LAN as the cluster
provides direct network access without an SSH tunnel.

## Prerequisites

The runner machine must have the following tools installed:

- Docker (for building and pushing images)
- `kubectl` (for cluster interaction)
- `helm` >= 3.x
- `pnpm` (used by the smoke test and migration job image)
- `curl` (used by the smoke test)

## /etc/hosts

Add an entry so the smoke test can resolve the app hostname:

```
<traefik-node-ip>  devops-challenge.local
```

Replace `<traefik-node-ip>` with the LAN IP of the k3s node running Traefik
(check with `kubectl get nodes -o wide`).

## Registering the Runner

1. In your GitHub repository, go to **Settings → Actions → Runners → New
   self-hosted runner**.
2. Select the OS of your runner machine and follow the on-screen instructions
   to download and configure the runner agent.
3. Start the runner as a service so it survives reboots:

   ```bash
   # Linux (systemd)
   sudo ./svc.sh install
   sudo ./svc.sh start
   ```

## Required Repository Secrets

| Secret | Description |
|--------|-------------|
| `KUBECONFIG` | Full kubeconfig pointing directly to the k3s API server LAN IP (`https://<ip>:6443`). Export with: `kubectl config view --raw --minify` |
| `GHCR_TOKEN` | GitHub PAT with `write:packages` scope |
| `POSTGRES_PASSWORD` | Password for the `devops` database user — must match the `password` key in the `postgres-credentials` Kubernetes Secret |

## Cluster Prerequisites

### 1. Install metrics-server (required for HPA)

k3s ships with metrics-server disabled by default:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### 2. Install Postgres (one-time, not managed by CI)

The Bitnami `postgresql` chart is installed once manually. CI only manages the
app chart.

#### 2a. Understand the credentials secret

The `postgres-credentials` Kubernetes Secret has three keys, each for a
different Postgres role:

| Key | Role | Used by |
|-----|------|---------|
| `postgres-password` | Built-in `postgres` superuser | DBA / admin tasks |
| `password` | Application user (`devops`) | The Next.js app and migration Job |
| `replication-password` | Replication standby user | Bitnami chart internals |

**The Bitnami chart automatically creates the `devops` user and the
`currencies` database on first install** using the values set in
`helm/postgres/values.yaml` (`global.postgresql.auth.username: devops`,
`global.postgresql.auth.database: currencies`). You do not need to create
them manually.

The `password` value here must match the `POSTGRES_PASSWORD` GitHub Actions
secret, since the app chart assembles the connection string from it.

#### 2b. Generate passwords

Use strong random passwords — one per role:

```bash
export PG_SUPERUSER_PASSWORD=$(openssl rand -base64 32)
export PG_APP_PASSWORD=$(openssl rand -base64 32)
export PG_REPLICATION_PASSWORD=$(openssl rand -base64 32)
```

Keep `PG_APP_PASSWORD` — you will need to add it to GitHub Secrets as
`POSTGRES_PASSWORD` in step 3.

#### 2c. Create the namespace and credentials secret

```bash
kubectl create namespace devops-challenge

kubectl create secret generic postgres-credentials \
  --from-literal=postgres-password="$PG_SUPERUSER_PASSWORD" \
  --from-literal=password="$PG_APP_PASSWORD" \
  --from-literal=replication-password="$PG_REPLICATION_PASSWORD" \
  -n devops-challenge
```

#### 2d. Install the chart

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm upgrade --install postgres bitnami/postgresql \
  -f helm/postgres/values.yaml \
  -n devops-challenge
```

Verify it comes up:

```bash
kubectl get pods -n devops-challenge
# postgres-postgresql-0 should reach Running/Ready
```
