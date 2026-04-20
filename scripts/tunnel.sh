#!/usr/bin/env bash
# tunnel.sh — Open an SSH tunnel to the k3s cluster (fallback access method).
#
# NOTE: The preferred access method from a Macbook is a static route — no
# foreground process required. See docs/networking.md for setup instructions.
# Use this tunnel only when a static route is not possible.
#
# Forwards:
#   localhost:8080  →  k3s-control:80    (Traefik ingress)
#   localhost:6443  →  k3s-control:6443  (k3s API server; skipped if already open)
#
# Usage:
#   SSH_HOST=<ubuntu-host> SSH_USER=<user> K3S_VM_IP=192.168.122.10 ./scripts/tunnel.sh
#
# Environment variables:
#   SSH_HOST   — hostname or IP of the Ubuntu host machine (required)
#   SSH_USER   — SSH username on the Ubuntu host (default: current user)
#   K3S_VM_IP  — IP of the k3s-control node (default: 192.168.122.10; see docs/networking.md)

set -euo pipefail

SSH_HOST="${SSH_HOST:?SSH_HOST must be set to the Ubuntu host IP or hostname}"
SSH_USER="${SSH_USER:-$(whoami)}"
K3S_VM_IP="${K3S_VM_IP:-192.168.122.10}"

echo "k3s VM IP: ${K3S_VM_IP}"

FORWARDS=()

# Forward Traefik ingress: local 8080 → k3s-control port 80 (via Ubuntu host)
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
