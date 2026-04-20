# Self-Hosted GitHub Actions Runner

The CI/CD pipeline deploys to a local k3s cluster that is not reachable from
GitHub's hosted runners. A self-hosted runner on the same LAN as the cluster
provides direct network access. Tailscale is used to connect the runner to the
k3s node's private network so the workflow can reach the cluster API server.

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

## Tailscale Setup

Tailscale creates a secure peer-to-peer connection between the GitHub Actions
runner and the k3s node, allowing the workflow to reach the cluster API server
(port 6443) without any manual tunnel setup.

### Step 1 — Create a Tailscale account

Go to [tailscale.com](https://tailscale.com) and sign up for a free personal
account. Verify your email to activate the account.

Note your **tailnet name** — it appears in the top-left of the admin console
in the format `<name>.ts.net`.

### Step 2 — Install Tailscale on the k3s node

SSH into the VM or host machine that runs the k3s cluster and run:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

Authenticate and enroll the node into your tailnet:

```bash
sudo tailscale up
```

A URL will be printed — open it in a browser to authorize the device. Once
authorized, the node will appear under **Machines** in the Tailscale admin
console.

### Step 3 — Note the Tailscale IP

In the admin console under **Machines**, find the k3s node and copy its
**Tailscale IP** (format: `100.x.y.z`). This IP is stable across reboots as
long as the node remains enrolled in the tailnet.

Verify connectivity from another machine on the tailnet:

```bash
ping <tailscale-ip>
curl -k https://<tailscale-ip>:6443/version
```

### Step 4 — Generate a reusable ephemeral auth key

In the Tailscale admin console, go to **Settings → Keys → Generate auth key**
and set the following options:

- **Reusable**: ✓ — required so the key works across multiple workflow runs
- **Ephemeral**: ✓ — runner nodes auto-expire from the tailnet after each job
- **Expiry**: 90 days

Click **Generate key** and copy the value immediately (it is only shown once).

### Auth Key Rotation

The auth key expires every 90 days. Before it expires:

1. Go to **Settings → Keys** in the Tailscale admin console.
2. Generate a new key with the same settings (Reusable, Ephemeral, 90-day expiry).
3. In your GitHub repository, go to **Settings → Secrets and variables →
   Actions** and update the `TAILSCALE_AUTHKEY` secret with the new value.

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
| `KUBECONFIG` | Full kubeconfig pointing to the k3s API server via its **Tailscale IP** (`https://<tailscale-ip>:6443`) with `insecure-skip-tls-verify: true`. See [Updating the KUBECONFIG Secret](#updating-the-kubeconfig-secret) below. |
| `GHCR_TOKEN` | GitHub PAT with `write:packages` scope |
| `TAILSCALE_AUTHKEY` | Reusable ephemeral Tailscale auth key (90-day expiry). Generate in the Tailscale admin console under **Settings → Keys**. See [Tailscale Setup](#tailscale-setup) above. |

## Updating the KUBECONFIG Secret

The `KUBECONFIG` secret must point to the k3s API server using the Tailscale
IP. The k3s TLS certificate was issued for the LAN IP, not the Tailscale IP,
so `insecure-skip-tls-verify: true` is required to avoid certificate errors.

1. On the k3s node, export the current kubeconfig:

   ```bash
   kubectl config view --raw --minify
   ```

2. Edit the output and make two changes to the `cluster` entry:
   - Change `server: https://<lan-ip>:6443` → `server: https://<tailscale-ip>:6443`
   - Add `insecure-skip-tls-verify: true` (remove any existing `certificate-authority-data` line)

   The cluster entry should look like:

   ```yaml
   clusters:
   - cluster:
       server: https://100.x.y.z:6443
       insecure-skip-tls-verify: true
     name: default
   ```

3. In your GitHub repository, go to **Settings → Secrets and variables →
   Actions** and update the `KUBECONFIG` secret with the modified kubeconfig.

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

## Using Tailscale for Local Development

If you have Tailscale installed on your laptop and the k3s node is enrolled in
the same tailnet, you can use `kubectl` and `helm` directly via the Tailscale
IP — no SSH tunnel required for cluster API access.

Export and patch the kubeconfig to use the Tailscale IP:

```bash
# On the k3s host — export the config
kubectl config view --raw --minify > /tmp/k3s-config.yaml

# Copy to your laptop, then patch the server URL and skip TLS verification
sed -i '' 's|https://.*:6443|https://<tailscale-ip>:6443|' /tmp/k3s-config.yaml
# Add insecure-skip-tls-verify: true under the cluster entry manually,
# or patch with:
sed -i '' '/server: https/a\\    insecure-skip-tls-verify: true' /tmp/k3s-config.yaml

export KUBECONFIG=/tmp/k3s-config.yaml
kubectl get nodes   # verify connectivity
```

> **Note**: `scripts/tunnel.sh` is still useful for forwarding the app's HTTP
> port (`8080 → 80` on the k3s host) so the smoke test can reach
> `devops-challenge.local:8080`. Tailscale does not replace that use case —
> see [docs/ssh-tunnel.md](ssh-tunnel.md) for details.
