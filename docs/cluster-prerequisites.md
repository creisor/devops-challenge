# Cluster Prerequisites

These are one-time setup steps that must be completed before the first CI
deploy. They configure the k3s cluster with the dependencies the application
requires.

> **Preferred method:** Run the Ansible playbook, which performs all of these
> steps idempotently:
>
> ```bash
> ansible-playbook ansible/prerequisites.yml -i ansible/inventory.yml
> ```
>
> The manual steps below are provided as a reference and fallback.

## Prerequisites

- `kubectl` configured to reach the cluster (see [docs/networking.md](networking.md))
- `helm` >= 3.x installed
- A GitHub PAT with `write:packages` scope (the same token used for `GHCR_TOKEN`)

## 1. Create the Namespace

```bash
kubectl create namespace devops-challenge
```

## 2. Create the GHCR Image Pull Secret

The cluster needs credentials to pull images from GitHub Container Registry:

```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<github-username> \
  --docker-password=<GHCR_TOKEN> \
  --namespace devops-challenge
```

## 3. Install the CloudNativePG Operator

[CloudNativePG](https://cloudnative-pg.io/) manages the PostgreSQL cluster. It
is cluster-scoped and only needs to be installed once:

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

## 4. Bootstrap the PostgreSQL Cluster

Apply the Cluster manifest to create the database and credentials:

```bash
kubectl apply -f helm/postgres/cluster.yaml
```

CloudNativePG provisions a PostgreSQL 17 pod, creates the `app` user and
`currencies` database, and generates two secrets automatically:

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

## 5. Install metrics-server (required for HPA)

k3s ships with metrics-server disabled by default:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

Verify:

```bash
kubectl top nodes   # should return CPU/memory usage after ~30s
```
