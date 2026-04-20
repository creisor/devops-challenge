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
