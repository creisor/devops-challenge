# SSH Tunnel — Fallback Access

> **Note:** The SSH tunnel is a fallback option. If your Macbook is on the same
> LAN as the Ubuntu host, the preferred approach is a static route — it requires
> no foreground process and survives shell restarts. See
> [docs/networking.md](networking.md) for setup instructions.

Use this tunnel if you cannot add a static route (e.g., the Ubuntu host is on a
different network segment, or you are working remotely).

## Network Topology

```
Developer Macbook
  │
  │  SSH tunnel (port-forward through Ubuntu host)
  ▼
Ubuntu host  ──►  k3s-control  192.168.122.10  (Traefik / API server)
                  (libvirt NAT, 192.168.122.0/24)
```

## Port Mapping

| Local port | Destination | Purpose |
|------------|-------------|---------|
| `8080` | `k3s-control:80` | Traefik ingress |
| `6443` | `k3s-control:6443` | k3s API server (skipped if port already in use) |

## Opening the Tunnel

```bash
export SSH_HOST=<ubuntu-host-ip>
export SSH_USER=<your-username>
export K3S_VM_IP=192.168.122.10   # static IP from docs/networking.md
./scripts/tunnel.sh
```

The script runs in the foreground. Press `Ctrl+C` to close it.

The `6443` forward is skipped automatically if that port is already in use
locally.

## /etc/hosts (tunnel mode)

When using the tunnel, traffic exits locally on port 8080. Add this entry
instead of the static-route `/etc/hosts` entry in `docs/networking.md`:

```
127.0.0.1  devops-challenge.local
```

After this, the app is reachable at `http://devops-challenge.local:8080`.

## Using kubectl / Helm via the Tunnel

Patch the kubeconfig to point at `localhost:6443` while the tunnel is open:

```bash
# On the k3s-control node — export the config
kubectl config view --raw --minify > /tmp/k3s-config.yaml

# Copy to Macbook, then patch the server URL
sed -i '' 's|https://.*:6443|https://localhost:6443|' /tmp/k3s-config.yaml

export KUBECONFIG=/tmp/k3s-config.yaml
kubectl get nodes   # verify connectivity
```

## Verifying Connectivity

```bash
# 1. Confirm the tunnel is open and the app responds
curl -sf http://devops-challenge.local:8080 | grep "Latest Crypto Prices"

# 2. Confirm kubectl can reach the API server
kubectl get pods -n devops-challenge

# 3. Run the full smoke test
./scripts/smoke-test.sh
```
