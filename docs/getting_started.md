# Getting Started

## Cluster Prerequisites

The Kubernetes cluster already existed, so the included Ansible playbook sets up the prereqs for the application.

### Before running the playbook

If you haven't set up the self-hosted Github Actions runner yet, you will have to set the `vault_github_runner_token` secret in `vault.yml` (see [ansible/vault.yml.example](ansible/vault.yml.example) for instructions on setting up `vault.yml`).

For instructions on the self-hosted GitHub Actions runner, see [github-actions.md](github-actions.md).

If you've already set this up, leave the variable unset, and these tasks will be skipped.

### Running the playbook

```
ansible-playbook ansible/prerequisites.yml -i ansible/inventory.yml --extra-vars "@ansible/vault.yml" --ask-vault-pass
```

## Macbook networkng setup

Take the one-time steps documented in the `Macbook` sections of [networking.md](networking.md); in a real cloud setup these would be handled by things like DNS and real certificate authorities.
