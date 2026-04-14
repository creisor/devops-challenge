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

### 2. Bootstrap Postgres (one-time, not managed by CI)

The Bitnami `postgresql` chart references a pre-existing Kubernetes Secret for
its credentials (`existingSecret: postgres-credentials` in
`helm/postgres/values.yaml`). **The secret must be created before the chart is
installed.** Follow these steps in order.

#### Step 1 — Create the namespace

```bash
kubectl create namespace devops-challenge
```

#### Step 2 — Generate passwords and create the credentials secret

The secret has three keys, one per Postgres role:

| Key | Role | Used by |
|-----|------|---------|
| `postgres-password` | Built-in `postgres` superuser | DBA / admin tasks |
| `password` | Application user (`devops`) | The Next.js app and migration Job |
| `replication-password` | Replication standby user | Bitnami chart internals |

Generate a strong random value for each:

```bash
export PG_SUPERUSER_PASSWORD=$(openssl rand -base64 32)
export PG_APP_PASSWORD=$(openssl rand -base64 32)
export PG_REPLICATION_PASSWORD=$(openssl rand -base64 32)
```

Then create the secret:

```bash
kubectl create secret generic postgres-credentials \
  --from-literal=postgres-password="$PG_SUPERUSER_PASSWORD" \
  --from-literal=password="$PG_APP_PASSWORD" \
  --from-literal=replication-password="$PG_REPLICATION_PASSWORD" \
  -n devops-challenge
```

Save `PG_APP_PASSWORD` — you will need to add it to GitHub Secrets as
`POSTGRES_PASSWORD` (step 3 below).

#### Step 3 — Install the Postgres chart

Now that the secret exists, the chart can be installed:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm upgrade --install postgres bitnami/postgresql \
  -f helm/postgres/values.yaml \
  -n devops-challenge
```

**The Bitnami chart automatically creates the `devops` user and the
`currencies` database** on first install, using the `password` key from the
secret and the `username`/`database` values in `helm/postgres/values.yaml`.
You do not need to create them manually.

Verify the pod comes up:

```bash
kubectl get pods -n devops-challenge
# postgres-postgresql-0 should reach Running/Ready
```
