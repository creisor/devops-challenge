# Networking — k3s Cluster Access

The k3s cluster runs on four libvirt VMs (`k3s-control`, `k3s-worker1`,
`k3s-worker2`, `k3s-worker3`) inside an Ubuntu host. The VMs are on a private
libvirt NAT network (`192.168.122.0/24`) that is not directly routable from
outside the Ubuntu host by default.

This document explains the network topology, how static IPs are assigned to the
VMs, and how to reach the cluster from a developer's Macbook without an SSH
tunnel.

## Network Topology

```
Developer Macbook
  │
  │  Static route: 192.168.122.0/24 via <ubuntu-host-ip>
  │  (IP forwarding already enabled by libvirt)
  ▼
Ubuntu host  ──►  k3s-control   192.168.122.10  (Traefik / API server)
             ──►  k3s-worker1   192.168.122.11
             ──►  k3s-worker2   192.168.122.12
             ──►  k3s-worker3   192.168.122.13
                  (libvirt NAT, 192.168.122.0/24)
```

The Ubuntu host acts as a gateway. libvirt enables IP forwarding on the host
automatically when the default network is active, so adding a static route on
the Macbook is sufficient — no additional configuration on the Ubuntu host is
required.

> **Why not a bridged interface?** The Ubuntu host uses a wireless NIC. Most
> 802.11 drivers do not support promiscuous MAC forwarding, which is required
> for a Linux bridge or macvtap interface. The static route approach avoids
> driver limitations entirely.

## Static IP Assignments

VMs receive static IPs via libvirt DHCP reservation (MAC address → IP). The
Ansible playbook (`ansible/prerequisites.yml`) applies these reservations
idempotently. To apply them manually, see the Ansible inventory
(`ansible/inventory.yml`) for the MAC addresses, then run:

```bash
virsh net-update default add ip-dhcp-host \
  "<host mac='<MAC>' name='k3s-control' ip='192.168.122.10'/>" \
  --live --config
```

Repeat for each VM, incrementing the IP (`.11`, `.12`, `.13`).

Verify all reservations are in place:

```bash
virsh net-dumpxml default | grep host
```

To force a VM to renew its DHCP lease immediately:

```bash
virsh domifaddr k3s-control   # check current IP
# If not yet updated, restart the VM's network interface or reboot the VM
```

## Ubuntu Host — Static LAN IP (Recommended)

The Ubuntu host's LAN IP is the gateway for all Macbook → cluster traffic. If
it changes (DHCP lease renewal, reboot, etc.) the static route on the Macbook
breaks and several config files need updating. Assign it a static IP to avoid
this.

**Option A — Router DHCP reservation (easiest)**

Find the Ubuntu host's LAN MAC address:

```bash
ip link show | grep -A1 "state UP" | grep link/ether
```

Add a DHCP reservation in your router's admin UI mapping that MAC to a fixed IP
(e.g. `192.168.0.196`). The host will always get the same IP from DHCP without
any OS-level changes.

**Option B — Netplan static IP on the Ubuntu host**

Edit `/etc/netplan/01-network-manager-all.yaml` (or whichever file configures
the LAN interface):

```yaml
network:
  version: 2
  ethernets:
    <interface>:          # e.g. enp0s31f6 — check with: ip link show
      dhcp4: no
      addresses: [192.168.0.196/24]
      routes:
        - to: default
          via: 192.168.0.1   # your router's IP
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
```

Apply: `sudo netplan apply`

---

## Ubuntu Host IP Changed — Recovery Steps

If the Ubuntu host's LAN IP changes despite the above, here is what to update:

**1. Update the Mac static route**

```bash
# Remove the old route (substitute the old IP)
sudo route delete -net 192.168.122.0/24 <old-ubuntu-ip>

# Add the new route
sudo route add -net 192.168.122.0/24 <new-ubuntu-ip>
```

Also update the LaunchDaemon plist at
`/Library/LaunchDaemons/net.192-168-122.route.plist` — replace the old IP with
the new one in the `ProgramArguments` array, then reload:

```bash
sudo launchctl unload /Library/LaunchDaemons/net.192-168-122.route.plist
sudo launchctl load  /Library/LaunchDaemons/net.192-168-122.route.plist
```

**2. Update ansible/inventory.yml**

Change the `ansible_host` value for `ubuntu_host` to the new IP:

```yaml
ubuntu_host:
  ansible_host: <new-ubuntu-ip>
```

**3. Verify the libvirt iptables FORWARD rule**

The rule that allows Macbook → VM traffic is scoped to `192.168.0.0/24` (the
subnet, not a specific host IP), so it survives an IP change within the same
/24. Confirm it is still present:

```bash
sudo iptables -L LIBVIRT_FWI -n -v | grep "192.168.0.0"
```

If missing, re-add it (see the libvirt hook setup below in this doc).

**Nothing else changes** — the kubeconfig, GitHub Actions secrets, and k3s
configuration all reference `192.168.122.10` (the k3s-control static libvirt
IP), which is independent of the Ubuntu host's LAN IP.

---

## Macbook — Static Route Setup

Once static IPs are assigned, add a route on your Macbook so that traffic to
the `192.168.122.0/24` subnet is forwarded through the Ubuntu host:

```bash
sudo route add -net 192.168.122.0/24 <ubuntu-host-ip>
```

Replace `<ubuntu-host-ip>` with the LAN IP of your Ubuntu machine (e.g.
`192.168.1.100`).

Verify the route is active:

```bash
route get 192.168.122.10
# "gateway:" should show <ubuntu-host-ip>

ping 192.168.122.10   # should reach k3s-control
```

### Making the Route Persistent on macOS

The `route add` command does not survive a reboot. To make it persistent, create
a `LaunchDaemon`:

1. Create `/Library/LaunchDaemons/net.192-168-122.route.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>net.192-168-122.route</string>
  <key>ProgramArguments</key>
  <array>
    <string>/sbin/route</string>
    <string>add</string>
    <string>-net</string>
    <string>192.168.122.0/24</string>
    <string><ubuntu-host-ip></string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
```

Replace `<ubuntu-host-ip>` with your Ubuntu host's LAN IP.

2. Load it:

```bash
sudo launchctl load /Library/LaunchDaemons/net.192-168-122.route.plist
```

## Ubuntu Host — libvirt iptables Forward Rule

By default, libvirt's iptables rules block new connections initiated from
outside the NAT network (only allowing return traffic). To allow the Macbook to
reach the VMs directly, one additional rule is needed and must survive libvirt
restarts.

**Add the rule now:**

```bash
sudo iptables -I LIBVIRT_FWI 1 \
  -d 192.168.122.0/24 -o virbr0 \
  -s 192.168.0.0/24 -j ACCEPT
```

**Make it persistent via a libvirt network hook** (re-applied whenever the
`default` network starts):

```bash
sudo mkdir -p /etc/libvirt/hooks
sudo tee /etc/libvirt/hooks/network << 'EOF'
#!/bin/bash
if [ "$1" = "default" ] && [ "$2" = "started" ]; then
    iptables -I LIBVIRT_FWI 1 \
      -d 192.168.122.0/24 -o virbr0 \
      -s 192.168.0.0/24 -j ACCEPT
fi
EOF
sudo chmod +x /etc/libvirt/hooks/network
```

Verify the rule is present after a reboot or `virsh net-destroy/start default`:

```bash
sudo iptables -L LIBVIRT_FWI -n -v | grep "192.168.0.0"
```

## Macbook — /etc/hosts

Add an entry so `devops-challenge.local` resolves to the k3s-control node
(Traefik routes traffic based on the `Host:` header):

```
192.168.122.10  devops-challenge.local
```

After this, the app is reachable at `http://devops-challenge.local`.

## Macbook — kubectl / Helm Access

Export the kubeconfig from the k3s node and point it at the static IP:

```bash
# On the k3s-control node
kubectl config view --raw --minify > /tmp/k3s-config.yaml

# Copy to Macbook, then verify the server URL uses the static IP
grep server /tmp/k3s-config.yaml
# Should show: server: https://192.168.122.10:6443
# If it shows 127.0.0.1, patch it:
sed -i '' 's|https://127.0.0.1:6443|https://192.168.122.10:6443|' /tmp/k3s-config.yaml

export KUBECONFIG=/tmp/k3s-config.yaml
kubectl get nodes   # verify connectivity
```

## SSH Tunnel (Fallback)

If you cannot add a static route (e.g., the Ubuntu host is not on the same LAN
segment), the SSH tunnel in `scripts/tunnel.sh` is available as a fallback.
See [docs/ssh-tunnel.md](ssh-tunnel.md) for instructions.
