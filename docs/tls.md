# TLS — Local HTTPS with mkcert

The cluster uses a [mkcert](https://github.com/FiloSottile/mkcert)-issued certificate
so the app is reachable at `https://devops-challenge.local` without browser warnings.

mkcert creates a local root CA, installs it in your Mac's Keychain, and issues a
certificate signed by that CA. No public CA or domain registration is required.

## One-time setup

**1. Install mkcert**

```bash
brew install mkcert
```

**2. Run the setup script**

From the repository root on your Macbook (requires `kubectl` access to the cluster):

```bash
./scripts/setup-tls.sh
```

The script:
- Installs the local CA into your Mac's Keychain (`mkcert -install`)
- Generates a certificate for `devops-challenge.local`
- Creates (or updates) the `devops-challenge-tls` TLS secret in the `devops-challenge` namespace

**3. Deploy**

Trigger a deploy (push to `main` or workflow dispatch) so Helm picks up the TLS
secret reference in the Ingress. After the deploy completes the app is available at:

```
https://devops-challenge.local
```

HTTP (`http://devops-challenge.local`) continues to work alongside HTTPS.

## Certificate renewal

mkcert certificates are valid for ~2.5 years. To renew, re-run the setup script:

```bash
./scripts/setup-tls.sh
```

The script uses `kubectl apply` with `--dry-run=client`, so re-running it is safe
and idempotent — it replaces the secret in-place.

## How it works

The Helm `Ingress` resource references the `devops-challenge-tls` secret via the
`ingress.tlsSecret` value. Traefik reads the secret and terminates TLS at the
ingress. The TLS secret is created out-of-band (not managed by Helm) so it persists
across deploys.

## CI smoke test

The GitHub Actions smoke test hits `http://192.168.122.10` directly (bypassing TLS)
so it does not require the mkcert CA to be trusted on the Ubuntu runner host.
