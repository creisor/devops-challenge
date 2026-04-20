# Self-Hosted GitHub Actions Runner

The CI/CD pipeline deploys to a local k3s cluster running inside a libvirt VM
on an Ubuntu host. The self-hosted runner runs on that same Ubuntu host, giving
it direct access to the libvirt NAT network — no tunnel or VPN required.

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
| `KUBECONFIG` | Full kubeconfig pointing to the k3s API server's libvirt IP (`https://<ip>:6443`). See [Finding the k3s IP](#finding-the-k3s-ip) and [Generating the KUBECONFIG Secret](#generating-the-kubeconfig-secret) below. |
| `GHCR_TOKEN` | GitHub PAT with `write:packages` scope |

## Finding the k3s IP

The k3s VM gets its IP from the libvirt NAT network. To find it, run the
following on the Ubuntu host:

```bash
virsh domifaddr k3s-control | awk '/ipv4/ {print $4}' | cut -d/ -f1
```

This prints the IP address to use for `kubectl` and the `KUBECONFIG` secret
(e.g. `192.168.122.x`). The IP may change if the VM is recreated.

## Generating the KUBECONFIG Secret

1. Find the k3s IP using the virsh command above.
2. On the k3s node, export the kubeconfig:

   ```bash
   kubectl config view --raw --minify
   ```

3. Confirm `server:` uses the libvirt IP (not `127.0.0.1`). If it does not,
   patch it:

   ```bash
   sed 's|https://127.0.0.1:6443|https://<libvirt-ip>:6443|' \
     /etc/rancher/k3s/k3s.yaml
   ```

4. In your GitHub repository, go to **Settings → Secrets and variables →
   Actions** and set the `KUBECONFIG` secret to the full kubeconfig content.

## Cluster Prerequisites

### 1. Create the GHCR image pull secret

The k3s cluster needs credentials to pull images from GHCR:

```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<github-username> \
  --docker-password=<GHCR_TOKEN> \
  --namespace devops-challenge
```

### 2. Install metrics-server (required for HPA)

k3s ships with metrics-server disabled by default:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### 3. Bootstrap Postgres (one-time, not managed by CI)

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
