#!/usr/bin/env bash
# tunnel.sh — Open an SSH tunnel to the k3s host for local developer access.
#
# Forwards:
#   localhost:8080  →  k3s-vm:80    (Traefik ingress; tunnelled via the Ubuntu host)
#   localhost:6443  →  k3s-vm:6443  (k3s API server; skipped if already open)
#
# The k3s cluster runs inside a libvirt VM on the Ubuntu host. The VM's IP is
# discovered automatically via `virsh domifaddr k3s-control` on the Ubuntu host.
#
# Usage:
#   SSH_HOST=<ubuntu-host> SSH_USER=<user> ./scripts/tunnel.sh
#
# Environment variables:
#   SSH_HOST   — hostname or IP of the Ubuntu host machine (required)
#   SSH_USER   — SSH username on the Ubuntu host (default: current user)
#   K3S_VM_IP  — override the auto-detected libvirt IP of the k3s VM (optional)

set -euo pipefail

SSH_HOST="${SSH_HOST:?SSH_HOST must be set to the Ubuntu host IP or hostname}"
SSH_USER="${SSH_USER:-$(whoami)}"

# Discover the k3s VM's libvirt IP from the Ubuntu host unless overridden
if [[ -z "${K3S_VM_IP:-}" ]]; then
  echo "Detecting k3s VM IP via virsh on ${SSH_HOST}..."
  K3S_VM_IP=$(ssh "${SSH_USER}@${SSH_HOST}" \
    "virsh domifaddr k3s-control | awk '/ipv4/ {print \$4}' | cut -d/ -f1")
  if [[ -z "$K3S_VM_IP" ]]; then
    echo "ERROR: could not detect k3s VM IP. Is the k3s-control VM running?" >&2
    echo "You can override by setting K3S_VM_IP=<ip> before running this script." >&2
    exit 1
  fi
fi
echo "k3s VM IP: ${K3S_VM_IP}"

FORWARDS=()

# Forward Traefik ingress: local 8080 → k3s VM port 80 (via Ubuntu host)
FORWARDS+=("-L" "8080:${K3S_VM_IP}:80")

# Only forward the k3s API port if it is not already in use locally
if lsof -ti:6443 > /dev/null 2>&1; then
  echo "Port 6443 is already in use locally — skipping k3s API forward"
else
  FORWARDS+=("-L" "6443:${K3S_VM_IP}:6443")
fi

echo "Opening SSH tunnel to ${SSH_USER}@${SSH_HOST}..."
echo "  localhost:8080 → ${K3S_VM_IP}:80  (Traefik ingress)"
[[ " ${FORWARDS[*]} " == *"6443"* ]] && echo "  localhost:6443 → ${K3S_VM_IP}:6443 (k3s API)"
echo "Press Ctrl+C to close the tunnel."

exec ssh \
  -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  "${FORWARDS[@]}" \
  "${SSH_USER}@${SSH_HOST}"
