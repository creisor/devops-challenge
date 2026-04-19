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

## Cluster Prerequisites

### 1. Install metrics-server (required for HPA)

k3s ships with metrics-server disabled by default:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### 2. Bootstrap Postgres (one-time, not managed by CI)

Postgres is managed by the [CloudNativePG](https://cloudnative-pg.io/)
operator. The operator creates the `app` user, the `currencies` database, and
all credentials automatically — no manual secret creation required.

#### Step 1 — Create the namespace

```bash
kubectl create namespace devops-challenge
```

#### Step 2 — Install the CloudNativePG operator

The operator is cluster-scoped and only needs to be installed once:

```bash
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update

helm upgrade --install cnpg cnpg/cloudnative-pg \
  --namespace cnpg-system \
  --create-namespace
```

Verify the operator is running:

```bash
kubectl get pods -n cnpg-system
# cnpg-cloudnative-pg-* should reach Running/Ready
```

#### Step 3 — Apply the Cluster manifest

```bash
kubectl apply -f helm/postgres/cluster.yaml
```

CNPG will provision a PostgreSQL 17 pod, create the `app` user and
`currencies` database, and generate credentials automatically. It creates two
secrets in the `devops-challenge` namespace:

| Secret | Contents |
|--------|----------|
| `postgres-app` | Application user credentials + `uri` connection string |
| `postgres-superuser` | Superuser (`postgres`) credentials |

The app Helm chart references `postgres-app` directly — no manual secret
management is needed.

Verify the cluster comes up:

```bash
kubectl get cluster -n devops-challenge
# postgres cluster should reach "Cluster in healthy state"

kubectl get pods -n devops-challenge
# postgres-1 should reach Running/Ready
```
