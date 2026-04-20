# SSH Tunnel — Local Developer Access

The k3s cluster runs inside a libvirt VM on an Ubuntu host. The VM's network
is on a private NAT (e.g. `192.168.122.0/24`) that is not directly reachable
from the developer's laptop. This document explains how to set up an SSH tunnel
through the Ubuntu host to reach the k3s VM.

## Network Topology

```
Developer laptop
  │
  │  SSH tunnel (port-forward through Ubuntu host)
  ▼
Ubuntu host  ──►  k3s VM (Traefik / API server)
                  (libvirt NAT, e.g. 192.168.122.x)
```

## Port Mapping

| Local port | Destination | Purpose |
|------------|-------------|---------|
| `8080` | `k3s-vm:80` | Traefik ingress (tunnelled via Ubuntu host) |
| `6443` | `k3s-vm:6443` | k3s API server (skipped if already forwarded) |

## Opening the Tunnel

```bash
export SSH_HOST=<ubuntu-host-ip>
export SSH_USER=<your-username>
./scripts/tunnel.sh
```

The script SSHes to the Ubuntu host, detects the k3s VM's libvirt IP
automatically via `virsh domifaddr k3s-control`, then sets up the forwards.
You can override the auto-detected IP with `K3S_VM_IP=<ip>` if needed.

The script runs in the foreground. Press `Ctrl+C` to close it.

The script automatically skips the `6443` forward if the port is already in
use locally (e.g. if you have a persistent tunnel running in another session).

## /etc/hosts

Add the following line so that `devops-challenge.local` resolves to localhost
(traffic is then forwarded through the tunnel to Traefik):

```
127.0.0.1  devops-challenge.local
```

After this, the app is reachable at `http://devops-challenge.local:8080`.

## Using kubectl / Helm Locally

Export and patch the kubeconfig so `kubectl` connects through the tunnel:

```bash
# On the k3s host — export the config
kubectl config view --raw --minify > /tmp/k3s-config.yaml

# Copy to your laptop, then patch the server URL
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
