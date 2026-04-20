# GitHub Actions — CI/CD Setup

The CI/CD pipeline builds, scans, and deploys the application using a
self-hosted GitHub Actions runner on the Ubuntu host. The runner has direct
access to the libvirt NAT network, so it can reach the k3s cluster without a
tunnel or VPN.

## Self-Hosted Runner

### Prerequisites

The runner machine (Ubuntu host) must have the following tools installed:

- Docker (for building and pushing images)
- `kubectl` (for cluster interaction)
- `helm` >= 3.x
- `curl` (used by the smoke test)

The Ansible playbook (`ansible/prerequisites.yml`) installs all of these.

### Registering the Runner

1. In your GitHub repository, go to **Settings → Actions → Runners → New
   self-hosted runner**.
2. Select **Linux** and follow the on-screen instructions to download and
   configure the runner agent. The registration token shown on that page is
   required by the Ansible playbook (`github_runner_token` variable).
3. Start the runner as a service so it survives reboots:

   ```bash
   # From the actions-runner directory
   sudo ./svc.sh install
   sudo ./svc.sh start
   ```

> The Ansible playbook handles steps 2 and 3 automatically when
> `github_runner_token` is provided.

## Required Repository Secrets

Set these under **Settings → Secrets and variables → Actions → Secrets**:

| Secret | Description |
|--------|-------------|
| `KUBECONFIG` | Full kubeconfig YAML pointing to `https://192.168.122.10:6443`. See [Generating the KUBECONFIG Secret](#generating-the-kubeconfig-secret) below. |
| `GHCR_TOKEN` | GitHub PAT with `write:packages` scope |

## Required Repository Variables

Set these under **Settings → Secrets and variables → Actions → Variables**:

| Variable | Value | Description |
|----------|-------|-------------|
| `K3S_IP` | `192.168.122.10` | Static IP of the k3s-control node. Used by the smoke test. See [docs/networking.md](networking.md). |

## Generating the KUBECONFIG Secret

1. On the k3s-control node, export the kubeconfig:

   ```bash
   kubectl config view --raw --minify
   ```

2. Confirm the `server:` field uses the static libvirt IP `192.168.122.10`. If
   it shows `127.0.0.1`, patch it:

   ```bash
   sed 's|https://127.0.0.1:6443|https://192.168.122.10:6443|' \
     /etc/rancher/k3s/k3s.yaml
   ```

3. In your GitHub repository, go to **Settings → Secrets and variables →
   Actions → Secrets** and set `KUBECONFIG` to the full kubeconfig content.

## Pipeline Overview

The workflow (`.github/workflows/deploy.yml`) runs on every push to `main` and
on manual dispatch. Steps:

1. **Checkout** — checks out the repository
2. **Log in to GHCR** — authenticates Docker with `GHCR_TOKEN`
3. **Build Docker image** — builds and tags with the commit SHA and `latest`
4. **Scan with Trivy** — fails on CRITICAL/HIGH CVEs not in `.trivyignore`
5. **Push to GHCR** — pushes both tags
6. **Write kubeconfig** — writes the `KUBECONFIG` secret to `~/.kube/config`
7. **Deploy with Helm** — runs `helm upgrade --install` with `--wait`
8. **Smoke test** — curls `http://<K3S_IP>` with a `Host: devops-challenge.local` header and checks for expected content
