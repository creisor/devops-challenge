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
| `POSTGRES_PASSWORD` | Password for the `devops` database user |

## Cluster Prerequisites

- The Bitnami `postgresql` chart must be installed before the first app deploy:

  ```bash
  # Add repo
  helm repo add bitnami https://charts.bitnami.com/bitnami
  helm repo update

  # Create namespace
  kubectl create namespace devops-challenge

  # Create credentials secret
  kubectl create secret generic postgres-credentials \
    --from-literal=postgres-password=<password> \
    --from-literal=password=<password> \
    --from-literal=replication-password=<password> \
    -n devops-challenge

  # Install Postgres
  helm upgrade --install postgres bitnami/postgresql \
    -f helm/postgres/values.yaml \
    -n devops-challenge
  ```

- `metrics-server` must be running for HPA to function. k3s ships with it
  disabled by default; enable it:

  ```bash
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  ```
