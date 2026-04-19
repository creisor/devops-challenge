#!/usr/bin/env bash
# tunnel.sh — Open an SSH tunnel to the k3s host for local developer access.
#
# Forwards:
#   localhost:8080  →  k3s-host:80   (Traefik ingress; port 80 requires root)
#   localhost:6443  →  k3s-host:6443 (k3s API server; skipped if already open)
#
# Usage:
#   SSH_HOST=<k3s-host> SSH_USER=<user> ./scripts/tunnel.sh
#
# Environment variables:
#   SSH_HOST  — hostname or IP of the k3s host machine (required)
#   SSH_USER  — SSH username (default: current user)

set -euo pipefail

SSH_HOST="${SSH_HOST:?SSH_HOST must be set to the k3s host IP or hostname}"
SSH_USER="${SSH_USER:-$(whoami)}"

FORWARDS=()

# Always forward Traefik ingress: local 8080 → remote 80
FORWARDS+=("-L" "8080:localhost:80")

# Only forward the k3s API port if it is not already in use locally
if lsof -ti:6443 > /dev/null 2>&1; then
  echo "Port 6443 is already in use locally — skipping k3s API forward"
else
  FORWARDS+=("-L" "6443:localhost:6443")
fi

echo "Opening SSH tunnel to ${SSH_USER}@${SSH_HOST}..."
echo "  localhost:8080 → ${SSH_HOST}:80  (Traefik ingress)"
[[ " ${FORWARDS[*]} " == *"6443"* ]] && echo "  localhost:6443 → ${SSH_HOST}:6443 (k3s API)"
echo "Press Ctrl+C to close the tunnel."

exec ssh \
  -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  "${FORWARDS[@]}" \
  "${SSH_USER}@${SSH_HOST}"
