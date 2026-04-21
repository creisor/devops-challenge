#!/usr/bin/env bash
# setup-tls.sh — Generate a mkcert certificate for devops-challenge.local and
# install it as a Kubernetes TLS secret.
#
# Run this once (or re-run to rotate the cert). The secret is not managed by
# Helm so it persists across deploys.
#
# Prerequisites:
#   - mkcert installed on this machine (brew install mkcert)
#   - kubectl configured to reach the cluster (KUBECONFIG set)
#   - devops-challenge namespace already exists

set -euo pipefail

DOMAIN="devops-challenge.local"
NAMESPACE="devops-challenge"
SECRET_NAME="devops-challenge-tls"
CERT_DIR="$(mktemp -d)"

cleanup() { rm -rf "$CERT_DIR"; }
trap cleanup EXIT

echo "==> Installing local CA (safe to re-run if already installed)"
mkcert -install

echo "==> Generating certificate for ${DOMAIN}"
mkcert -cert-file "${CERT_DIR}/tls.crt" -key-file "${CERT_DIR}/tls.key" "${DOMAIN}"

echo "==> Creating/updating TLS secret in namespace ${NAMESPACE}"
kubectl create secret tls "${SECRET_NAME}" \
  --cert="${CERT_DIR}/tls.crt" \
  --key="${CERT_DIR}/tls.key" \
  --namespace="${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Done. Secret '${SECRET_NAME}' is ready in namespace '${NAMESPACE}'."
echo "    Run 'helm upgrade' or trigger a deploy to activate TLS on the ingress."
