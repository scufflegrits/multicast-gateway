# Multicast Reference Guide — Proxmox / Linux (Debian 13)

**Coverage: IPv4 multicast only.** IPv6/MLD configuration and validation are
outside this guide. mcgw itself retains its separate IPv4/IPv6 design scope.

| Field          | Detail                               |
|----------------|--------------------------------------|
| Version        | 1.0.3                                |
| Last Updated   | 20261017                             |
| Author         | sysadmin                             |
| Filename       | MulticastReference-LinuxDebian_r1.0.3.md |

---

## Scope and command use

| Item | Boundary |
|---|---|
| Relationship to mcgw | Supporting platform reference; [architecture](../architecture.md) owns mcgw requirements |
| Lab examples | VLAN 2601, hostnames, interface names and addresses illustrate a topology; substitute verified site values |
| Evidence | Primary-source review on 2026-10-17; no new device/VM tests executed; exact deployment builds remain unqualified |
| Inspect | `show`, `Get-*`, `ip ... show`, `cat`, status and bounded captures collect evidence; privileges may still be needed |
| Change | Configuration stanzas, route/address additions, firewall edits, package installation and service commands change state; select explicitly and retain rollback settings |
| Active test | Senders/joins create traffic/membership; choose interface, rate, duration and destination deliberately |
| Capture limit | Capture visibility is not application receipt; check drops and observation point |

## Revision History

| Version | Date     | Author   | Change Summary                                                                          |
|---------|----------|----------|-----------------------------------------------------------------------------------------|
| Review 2 | 20261017 | scufflegrits | Second review corrections (F01, F02, F06, F21, F22); see architecture review §7 |
| Review | 20261017 | scufflegrits | IPv4-only scope; technical corrections, clickable navigation, acronym and verification-source appendices; filename/version retained |
| 1.0.3   | 20261016 | sysadmin | Section 11 deep dive fully written (11.1–11.7) and extended with 11.8 socket-level controls and 11.9 deep dive troubleshooting; added 3.4 firewalls (guest nftables/ufw, Proxmox VM firewall); added troubleshooting 10.6 and 10.7; glossary additions |
| 1.0.2   | 20261016 | sysadmin | Technical corrections: iperf3 replaced (sections 5.3 and 6.2 retitled) with iperf (iperf2) for multicast; mcjoin flags corrected (-v, -l, -r); pimd dense-mode claims removed; smcroute SSM and same-interface forwarding corrected; /proc/net/igmp conversion example fixed; IGMP timeout arithmetic fixed; rp_filter/iptables scope on the Proxmox bridge clarified; 11.4 limit description corrected; platform note updated; filename field and section 11 TOC link fixed |
| 1.0.1   | 20250519 | sysadmin | Added section 4.3 multi-interface selection; section 11 deep dive headers; glossary updates |
| 1.0.0   | 20250517 | sysadmin | Initial release                                                                         |

---

> **Platform Note**
> The target platform is Proxmox VE 9.x on Debian 13 (Trixie). This guide was
> first written against Proxmox VE 8.x on Debian 12 (Bookworm), before Debian
> 13 was released. Package names, kernel bridge behavior, and configuration
> paths are expected to be the same on PVE 9.x; any known differences are
> noted where applicable. Verify package availability on Debian 13 with
> `apt-cache show <package>` before deploying. RHEL 9/10 systems are covered
> by MulticastReference-LinuxRHEL9-10_r1.0.0.md.

---

## Table of Contents

- [Scope and command use](#scope-and-command-use)
- [Revision History](#revision-history)
- [1. Overview](#1-overview)
- [2. Proxmox Host Bridge Configuration](#2-proxmox-host-bridge-configuration)
  - [2.1 Linux Bridge and Multicast](#21-linux-bridge-and-multicast)
  - [2.2 bridge-mcsnooping Behavior](#22-bridge-mcsnooping-behavior)
  - [2.3 Recommended Bridge Configuration](#23-recommended-bridge-configuration)
  - [2.4 VLAN-Aware Bridge and Multicast](#24-vlan-aware-bridge-and-multicast)
  - [2.5 Bond Interface and Multicast](#25-bond-interface-and-multicast)
  - [2.6 Applying and Verifying Bridge Changes](#26-applying-and-verifying-bridge-changes)
- [3. VM NIC Configuration for Multicast VLANs](#3-vm-nic-configuration-for-multicast-vlans)
  - [3.1 Proxmox VM NIC and VLAN Tag](#31-proxmox-vm-nic-and-vlan-tag)
  - [3.2 Verification at the Host Level](#32-verification-at-the-host-level)
  - [3.3 Multicast Interface Selection on Multi-Homed Machines](#33-multicast-interface-selection-on-multi-homed-machines)
    - [How Linux Selects the Multicast Interface](#how-linux-selects-the-multicast-interface)
    - [The Problem With Multiple Interfaces](#the-problem-with-multiple-interfaces)
    - [IGMP Join Interface Selection](#igmp-join-interface-selection)
    - [Mechanism 1 — Add a Specific Multicast Route (Recommended)](#mechanism-1--add-a-specific-multicast-route-recommended)
    - [Mechanism 2 — Bind the Application to a Specific Interface](#mechanism-2--bind-the-application-to-a-specific-interface)
    - [Mechanism 3 — Set Interface Route Metric](#mechanism-3--set-interface-route-metric)
    - [Proxmox Host — Verifying bond999 and vmbr999 Are Not Blocking Multicast](#proxmox-host--verifying-bond999-and-vmbr999-are-not-blocking-multicast)
    - [Verifying Which Interface Multicast Is Using](#verifying-which-interface-multicast-is-using)
    - [Recommendation for This Environment](#recommendation-for-this-environment)
  - [3.4 Firewalls and Multicast](#34-firewalls-and-multicast)
    - [Guest Firewall — nftables](#guest-firewall--nftables)
    - [Guest Firewall — ufw](#guest-firewall--ufw)
    - [Proxmox Firewall for the VM](#proxmox-firewall-for-the-vm)
- [4. Debian 13 Guest — Required Packages](#4-debian-13-guest--required-packages)
  - [4.1 Package Overview](#41-package-overview)
  - [4.2 Installation](#42-installation)
- [5. Debian 13 Guest — Multicast Receiver Configuration](#5-debian-13-guest--multicast-receiver-configuration)
  - [5.1 Joining a Multicast Group Manually](#51-joining-a-multicast-group-manually)
  - [5.2 Using mcjoin as a Receiver](#52-using-mcjoin-as-a-receiver)
  - [5.3 Using iperf (iperf2) as a Receiver](#53-using-iperf-iperf2-as-a-receiver)
  - [5.4 Using smcroute as a Static Receiver](#54-using-smcroute-as-a-static-receiver)
  - [5.5 Using pimd as a Dynamic Receiver](#55-using-pimd-as-a-dynamic-receiver)
- [6. Debian 13 Guest — Multicast Sender Configuration](#6-debian-13-guest--multicast-sender-configuration)
  - [6.1 Using mcjoin as a Sender](#61-using-mcjoin-as-a-sender)
  - [6.2 Using iperf (iperf2) as a Sender](#62-using-iperf-iperf2-as-a-sender)
  - [6.3 Using smcroute for Static Sending](#63-using-smcroute-for-static-sending)
- [7. smcroute vs pimd — Which to Use](#7-smcroute-vs-pimd--which-to-use)
  - [7.1 smcroute Overview](#71-smcroute-overview)
  - [7.2 pimd Overview](#72-pimd-overview)
  - [7.3 Recommendation for This Environment](#73-recommendation-for-this-environment)
- [8. systemd Service Configuration](#8-systemd-service-configuration)
  - [8.1 smcroute as a systemd Service](#81-smcroute-as-a-systemd-service)
  - [8.2 pimd as a systemd Service](#82-pimd-as-a-systemd-service)
- [9. Testing and Verification](#9-testing-and-verification)
  - [9.1 Verification Commands — Proxmox Host](#91-verification-commands--proxmox-host)
  - [9.2 Verification Commands — Debian Guest](#92-verification-commands--debian-guest)
  - [9.3 Worked End-to-End Test Scenario](#93-worked-end-to-end-test-scenario)
- [10. Troubleshooting](#10-troubleshooting)
  - [10.1 Multicast Not Leaving the VM](#101-multicast-not-leaving-the-vm)
  - [10.2 Multicast Not Arriving at the VM](#102-multicast-not-arriving-at-the-vm)
  - [10.3 IGMP Join Not Seen by Switch](#103-igmp-join-not-seen-by-switch)
  - [10.4 Multicast Works Briefly Then Stops](#104-multicast-works-briefly-then-stops)
  - [10.5 Bridge Delivering Multicast to Wrong VMs](#105-bridge-delivering-multicast-to-wrong-vms)
  - [10.6 Multicast Reaches the VM but Not the Application](#106-multicast-reaches-the-vm-but-not-the-application)
  - [10.7 Multicast Interrupted After Live Migration](#107-multicast-interrupted-after-live-migration)
- [11. Deep Dive — Advanced Multicast Interface Control (Debian Guest VMs)](#11-deep-dive--advanced-multicast-interface-control-debian-guest-vms)
  - [11.1 Policy Routing with ip rule](#111-policy-routing-with-ip-rule)
  - [11.2 Multicast Routing Tables](#112-multicast-routing-tables)
  - [11.3 rp_filter — Reverse Path Filtering](#113-rp_filter--reverse-path-filtering)
  - [11.4 igmp_max_memberships — Host and Guest Limits](#114-igmp_max_memberships--host-and-guest-limits)
  - [11.5 VRFs — Virtual Routing and Forwarding](#115-vrfs--virtual-routing-and-forwarding)
  - [11.6 smcroute Interface Binding in Multi-Interface Environments](#116-smcroute-interface-binding-in-multi-interface-environments)
  - [11.7 pimd Interface Binding in Multi-Interface Environments](#117-pimd-interface-binding-in-multi-interface-environments)
  - [11.8 Socket-Level Controls — IP_MULTICAST_ALL and Receive Buffers](#118-socket-level-controls--ip_multicast_all-and-receive-buffers)
  - [11.9 Deep Dive Troubleshooting](#119-deep-dive-troubleshooting)
- [12. Glossary](#12-glossary)
- [Appendix A — Acronyms and meanings](#appendix-a--acronyms-and-meanings)
- [Appendix B — Verification sources](#appendix-b--verification-sources)
  - [Qualification still required](#qualification-still-required)

## 1. Overview

This document covers multicast configuration for Proxmox VE hosts and Debian 13
guest VMs in an environment where intra-VLAN multicast is required between VMs
running on Proxmox servers and physical clients connected to Cisco Catalyst
access layer switches.

The architecture is:

```
Debian VM (PVE0x, VLAN 2601)
    ↓ tap interface
vmbr999 Linux bridge (VLAN-aware, selected snooping/flooding policy)
    ↓ bond999 (LACP 802.3ad)
SWITCH01
    ↓ trunk
SWITCH02
    ↓ access port Gi1/0/1
Physical client (VLAN 2601)
```

Multicast is intra-VLAN only. No inter-VLAN multicast routing is required.
Multicast group addresses are in the 239.0.0.0/8 administratively scoped range.
The Cisco switches handle IGMP snooping and querier duties as described in the
[Cisco guide](MulticastReference-Cisco_r1.0.0.md). The Proxmox bridge follows the lab's deliberate flooding policy. A working snooping
configuration is also valid; guest socket membership remains separate.

---

## 2. Proxmox Host Bridge Configuration

### 2.1 Linux Bridge and Multicast

The Proxmox host uses a Linux kernel bridge (vmbr999) to connect VM tap
interfaces to the physical network via the bond interface. The Linux bridge
has its own IGMP snooping implementation that operates independently of the
upstream Cisco switches.

By default, Linux bridge IGMP snooping is enabled. This creates a two-layer
snooping situation:

```
VM receiver joins on its guest interface
    ↓ report traverses tap and vmbr999 toward physical querier
    ↓ bridge learns VM port membership when snooping is enabled
    ↓ physical switch learns membership on the host-facing uplink
Queries travel from the physical querier toward the VM.
```

A bridge need not run its own querier when it receives usable queries from the
physical network. Inspect per-VLAN query propagation, bridge multicast database
(MDB), router-port learning and VM reports before changing snooping.

| Policy | Tradeoff |
|---|---|
| Snooping enabled | Limit delivery to interested ports; requires healthy membership/query state |
| Snooping disabled | Deliberate multicast flooding within VLAN forwarding constraints; more guest bandwidth/CPU |

The illustrated lab may choose flooding. It is not a universal fix or a mcgw
requirement; increasing multicast load is not necessarily “slight.” See L1.

### 2.2 bridge-mcsnooping Behavior

The `bridge-mcsnooping` option controls the Linux bridge IGMP snooping behavior.

| Setting                  | Behavior                                                      |
|--------------------------|---------------------------------------------------------------|
| bridge-mcsnooping 1      | Default. Bridge performs its own IGMP snooping.               |
| bridge-mcsnooping 0      | Bridge forwards all multicast to all ports. Transparent mode. |

With `bridge-mcsnooping 0`:

- The bridge does not intercept or act on IGMP traffic
- All multicast frames are forwarded to all tap interfaces in the VLAN
- IGMP joins and reports pass through the bridge unmodified to the switch
- Upstream switches still maintain their own snooping state; guest socket
  membership remains necessary
- VM-facing ports may receive additional multicast in their VLAN; guest
  NIC/socket filtering remains separate from bridge forwarding

This increases the per-VM multicast load slightly since VMs may receive additional
multicast in the VLAN rather than only subscribed groups. For a controlled
environment using 239.x.x.x private range groups with a limited number of VMs
per VLAN, measure whether the flooding load is acceptable; do not assume it is.

### 2.3 Recommended Bridge Configuration

Example flooding-mode `/etc/network/interfaces` stanza for the illustrated lab;
verify existing VLAN/bond/loop policy before applying, rather than copying it to all hosts:

```
auto vmbr999
iface vmbr999 inet manual
        bridge-ports bond999
        bridge-stp off
        bridge-fd 0
        bridge-vlan-aware yes
        bridge-vids 2-665 667-4094
        bridge-pvid 999
        bridge-mcsnooping 0
```

The change from the default is the addition of `bridge-mcsnooping 0`. All
other parameters remain unchanged.

Rationale for each parameter in the context of multicast:

```
bridge-stp off       STP disabled is a lab topology choice, not a multicast
                     prerequisite. Validate loop prevention and switch edge/BPDU
                     policy for the host bridge before selecting this value.

bridge-fd 0          Forward delay of 0 seconds. Ensures the bridge does not
                     delay multicast forwarding when a tap interface comes up.

bridge-vlan-aware yes Required for VLAN-tagged VM NICs to pass the correct
                     VLAN to the upstream switch.

bridge-mcsnooping 0  Disables Linux bridge IGMP snooping. Makes the bridge
                     transparent to multicast and delegates all snooping
                     decisions to the upstream Cisco switches.
```

Apply only to hosts for which this policy was selected. Existing host addressing,
VLAN exclusions, loop protection and management paths must be preserved.

### 2.4 VLAN-Aware Bridge and Multicast

The `bridge-vlan-aware yes` setting enables per-VLAN forwarding on the Linux
bridge. This is required for VM NICs with VLAN tags to function correctly.

In the context of multicast, VLAN-aware mode means:

- Multicast frames tagged with VLAN 2601 are forwarded only to tap interfaces
  that are members of VLAN 2601 (i.e. VMs with `tag=2601` in their NIC config)
- This VLAN isolation is enforced at the bridge level regardless of
  bridge-mcsnooping setting
- With `bridge-mcsnooping 0`, all multicast within VLAN 2601 goes to all
  VLAN 2601 tap interfaces, but not to tap interfaces in VLAN 2602

This means `bridge-mcsnooping 0` does not cause cross-VLAN multicast leakage.
The VLAN-aware bridge maintains VLAN isolation while forwarding all intra-VLAN
multicast to all members of that VLAN.

### 2.5 Bond Interface and Multicast

The PVE hosts use LACP 802.3ad bonded interfaces (bond999) as the uplink to
SWITCH01. Multicast traffic passes correctly through a bonded interface with
the following considerations:

IGMP join frames sent by VMs traverse the bond to reach the upstream switch.
The bond hash policy (`bond-xmit-hash-policy layer2+3`) determines which bond
member carries each flow. Multicast traffic uses the multicast destination MAC
and IP for hashing. This means:

- Different multicast groups may exit via different bond members
- The upstream switch (SWITCH01) sees IGMP joins arriving on whichever bond
  member the hash selects
- Since both bond members are part of the same port-channel on SWITCH01, the
  switch processes the IGMP join correctly regardless of which member it
  arrives on
- No special bond configuration is required for multicast to pass correctly

The bond configuration for reference:

```
auto bond999
iface bond999 inet manual
        bond-slaves nic2 nic7
        bond-miimon 100
        bond-mode 802.3ad
        bond-xmit-hash-policy layer2+3
        bond-downdelay 200
        bond-updelay 200
        bond-lacp-rate fast
```

No changes to the bond configuration are needed for multicast support.

### 2.6 Applying and Verifying Bridge Changes

After editing `/etc/network/interfaces`, apply the changes without a full reboot:

```
sudo ifreload -a
```

Verify the bridge-mcsnooping setting is active:

```
cat /sys/class/net/vmbr999/bridge/multicast_snooping
```

Expected output after setting `bridge-mcsnooping 0`:

```
0
```

If the output is `1`, the setting has not been applied. Re-check the interfaces
file for syntax errors and re-run `ifreload -a`.

Verify bridge VLAN membership is intact after reload:

```
bridge vlan show
```

Verify bond members are up:

```
cat /proc/net/bonding/bond999
```

---

## 3. VM NIC Configuration for Multicast VLANs

### 3.1 Proxmox VM NIC and VLAN Tag

For a VM to participate in multicast on a specific VLAN, its NIC must be
connected to the VLAN-aware bridge with the correct VLAN tag. This is
configured in the VM's configuration file.

Location of VM configuration files:

```
/etc/pve/qemu-server/<vmid>.conf
```

Example NIC configuration for a VM on VLAN 2601:

```
net0: virtio=BC:24:11:AA:BB:CC,bridge=vmbr999,tag=2601
```

Key parameters:

```
bridge=vmbr999    The VM NIC connects to the VLAN-aware bridge
tag=2601          The bridge presents VLAN 2601 to this NIC
                  The VM OS sees an untagged interface
                  The bridge handles the 802.1Q tagging toward the switch
```

Inside the VM guest OS, the NIC appears as a standard untagged Ethernet
interface. The VM does not need to configure 802.1Q VLAN tagging. Multicast
joins sent by the VM are tagged with VLAN 2601 by the bridge before being
forwarded to the upstream switch.

### 3.2 Verification at the Host Level

Find the tap interface associated with a VM NIC:

```
# List all tap interfaces
ip link show type tap

# Or find the taps for a specific VM (replace 101 with the VM ID)
ls /sys/class/net/ | grep '^tap101i'
```

Alternatively, the tap interface name follows the pattern `tap<vmid>i<nic>`:

```
# For VM ID 101, NIC 0
tap101i0
```

Capture traffic on the tap interface to verify multicast frames are passing:

```
sudo tcpdump -i tap101i0 -nn -e multicast
```

Capture on the bond interface to verify multicast is reaching the switch:

```
sudo tcpdump -i bond999 -nn -e 'vlan 2601 and multicast'
```

### 3.3 Multicast Interface Selection on Multi-Homed Machines

A multi-homed Linux machine has more than one active network interface. This is
common for Debian guest VMs on Proxmox that have separate NICs for management,
data, and VLAN access. Incorrect multicast interface selection is a frequent
cause of multicast failure and must be understood and controlled explicitly.

#### How Linux Selects the Multicast Interface

Linux selects the outbound interface for multicast traffic by consulting the
routing table, specifically looking for the route that covers the multicast
destination address. For 239.x.x.x destinations, the kernel looks for a route
matching 239.0.0.0/8 or falls back to the default route (0.0.0.0/0).

Check existing multicast routes:

```
ip route show table all | grep -E '22[4-9]\.|23[0-9]\.'
```

Check which interface the kernel would use for a specific multicast address:

```
ip route get 239.1.1.1
```

The `dev` field in the output shows which interface the kernel selects. If this
is not the intended VLAN interface, action is required.

#### The Problem With Multiple Interfaces

Consider a Debian VM with three NICs:

```
eth0 — management,  IP 10.32.200.x,  gateway 10.32.200.254, metric 100
eth1 — VLAN 2601,   IP 192.168.1.10, no gateway,            metric 100
eth2 — external,    IP 10.0.0.x,     gateway 10.0.0.1,      metric 50
```

Running `ip route get 239.1.1.1` on this machine will return eth2 because it
has the lowest metric default route. Multicast traffic exits eth2, never reaches
VLAN 2601, and the physical client on SWITCH02 receives nothing.

#### IGMP Join Interface Selection

The same routing table logic applies to IGMP joins. The IGMP membership report
is sent out whichever interface the kernel selects for the multicast destination,
not necessarily the interface the application intends to receive traffic on:

```
Application joins 239.1.1.1
    ↓
Kernel consults routing table for 239.1.1.1
    ↓
Default route via eth2 wins (lowest metric)
    ↓
IGMP join exits eth2 instead of eth1
    ↓
SWITCH01 sees no join on VLAN 2601
    ↓
Multicast never delivered to the physical client VLAN
```

#### Mechanism 1 — Add a Specific Multicast Route (Recommended)

Add an explicit route for the 239.0.0.0/8 range via the correct interface.
This overrides the default route for all multicast destinations and is a
system-wide setting that affects all applications.

Add the route temporarily (lost on reboot):

```
sudo ip route add 239.0.0.0/8 dev eth1
```

Verify the route is in place and the correct interface is now selected:

```
ip route show | grep 239
ip route get 239.1.1.1
```

Make the route persistent in `/etc/network/interfaces`:

```
auto eth1
iface eth1 inet static
    address 192.168.1.10/24
    post-up ip route add 239.0.0.0/8 dev eth1
    pre-down ip route del 239.0.0.0/8 dev eth1
```

Remove the route if no longer needed:

```
sudo ip route del 239.0.0.0/8 dev eth1
```

#### Mechanism 2 — Bind the Application to a Specific Interface

Explicit membership-interface selection controls where the socket joins; an
outgoing multicast-interface setting constrains sends. Source binding is a
separate operation and must not be mistaken for full egress enforcement.

In mcjoin, use the `-i` flag:

```
# Receiver — join group on eth1 explicitly
mcjoin -i eth1 -p 5001 239.1.1.1

# Sender — send from eth1 explicitly
mcjoin -i eth1 -s -p 5001 239.1.1.1
```

In iperf (iperf2), bind the receiver to the group with `%<device>` and the
sender to the local interface IP. (iperf3 does not support multicast.)

```
# Receiver
iperf -s -u -B 239.1.1.1%eth1 -p 5001 -i 1

# Sender
iperf -c 239.1.1.1 -u -B 192.168.1.10 -p 5001 -T 1
```

Using the `ip` command to join a group on a specific interface:

```
sudo ip addr add 239.1.1.1/32 dev eth1 autojoin
```

This explicitly joins the group on eth1 regardless of what the routing table
selects for outbound traffic.

#### Mechanism 3 — Set Interface Route Metric

Assign a lower metric to the multicast interface so it wins the routing table
comparison against competing default routes. This is a system-wide approach
that affects all traffic, not just multicast.

Temporarily set a lower metric on eth1:

```
sudo ip route add default dev eth1 metric 10
```

Persistently via `/etc/network/interfaces`:

```
auto eth1
iface eth1 inet static
    address 192.168.1.10/24
    metric 10
```

Note: Adjusting default route metrics affects all traffic routing on the
machine. Use Mechanism 1 (specific multicast route) in preference to this
approach when only multicast routing needs to be corrected.

#### Proxmox Host — Verifying bond999 and vmbr999 Are Not Blocking Multicast

The Proxmox host itself sits between the VM and the upstream switch. Even with
the guest VM correctly configured, the host's bond999 and vmbr999 can
inadvertently block or mangle multicast frames. The following checks verify
the host is transparent to multicast.

**Verify the bridge snooping state matches the selected policy:**

```
cat /sys/class/net/vmbr999/bridge/multicast_snooping
```

Expected: the chosen snooping policy (0 for deliberate flooding; 1 for working
snooping), not a universal required value. A value of `1` does not by itself
show that a querier is missing or that delivery will fail. With snooping
enabled, confirm that queries arrive on the VLAN, that VM tap ports appear in
the bridge multicast database (MDB), that the uplink is learned as a router
port, and that the tap and bond carry the expected VLAN:

```
sudo tcpdump -i bond999 -nn -e -c 20 igmp
bridge -d mdb show dev vmbr999
bridge vlan show
```

If queries are absent or memberships are not learned, correct the querier or
VLAN path (see [2.1](#21-linux-bridge-and-multicast)). Disabling snooping is
the deliberate-flooding alternative described in
[2.2](#22-bridge-mcsnooping-behavior), not a repair for a missing querier. To
select flooding deliberately:

```
# Add bridge-mcsnooping 0 to the vmbr999 stanza in /etc/network/interfaces
sudo ifreload -a
# Rollback: remove the line (or set bridge-mcsnooping 1) and reload again
```

**Verify no iptables or nftables rules are blocking multicast on the host:**

Bridged frames between a tap and the bond can be filtered at more than one
layer:

| Layer | When it sees bridged frames |
|---|---|
| nftables `bridge` family | Always applies to bridged frames; does not require `br_netfilter` (L10, L11) |
| nftables `netdev` family | Ingress/egress hooks on the tap, bond or bridge port devices |
| iptables and nftables `ip`/`inet` families | Only for bridged IPv4 when `br_netfilter` is loaded and `net.bridge.bridge-nf-call-iptables` is 1; the Proxmox firewall enables this when it is active |

A value of 0 for `net.bridge.bridge-nf-call-iptables`, or an absent key, only
means the IP-family compatibility hooks do not see bridged VM traffic. It does
not mean bridge filtering can be skipped: inspect the complete applicable
rulesets and the Proxmox datacenter, host and VM firewall policy regardless.

Inspect complete rulesets with counters rather than grepping for group
addresses. A grep misses chain default policies, set or map lookups, and rules
that match by interface, protocol or port rather than by 239/224 address:

```
sudo nft -a list ruleset
sudo iptables -S
sudo iptables -L FORWARD -n -v --line-numbers
pve-firewall status
```

Check each chain's policy and which counters increase while the test traffic
runs. Before changing anything, identify which manager owns the matching rule
(Proxmox firewall `.fw` files, a host nftables configuration, or another
tool); a direct `iptables` or `nft` edit to a managed ruleset is overwritten on
the next reload and can bypass that manager's policy. Make the narrowest change
in the owning manager, scoped to the bridge or port, the group and the UDP port,
and record how to roll it back. For the Proxmox firewall, see
[3.4](#34-firewalls-and-multicast).

**Verify the bond is passing multicast frames:**

```
sudo tcpdump -i bond999 -nn -e multicast -c 20

sudo tcpdump -i bond999 -nn -e 'multicast and not (ether dst 01:80:c2:00:00:00 or ether dst 01:00:0c:cc:cc:cd)' -c 20
```

You should see multicast frames tagged with the expected VLAN. If nothing
appears but the VM is sending, check the bond member status:

```
cat /proc/net/bonding/bond999
```

Both bond members (nic2 and nic7) must show `MII Status: up`. A degraded bond
with one member down may cause hash-based multicast flows to be dropped if the
active member changes.

**Verify the tap interface is in the correct VLAN on the bridge:**

```
bridge vlan show dev tap<vmid>i0
```

The tap interface should show only the VM's VLAN (e.g. 2601) as a member. If
the tap appears in the wrong VLAN or is untagged with the wrong PVID, the VM
NIC tag in `/etc/pve/qemu-server/<vmid>.conf` does not match.

Fix — correct the VLAN tag in the VM config:

```
# Edit the VM config (VM must be stopped or use Proxmox GUI for hot changes)
sudo nano /etc/pve/qemu-server/<vmid>.conf

# Correct line example:
net0: virtio=BC:24:11:AA:BB:CC,bridge=vmbr999,tag=2601
```

**Verify the host kernel is not dropping multicast due to rp_filter:**

```
sysctl net.ipv4.conf.bond999.rp_filter
sysctl net.ipv4.conf.vmbr999.rp_filter
```

rp_filter is an IP-layer check. It applies only to packets delivered to the
Proxmox host's own IP stack (for example, traffic to a management address on
vmbr999). Frames bridged between a VM tap and bond999 are not IP-routed by the
host and are not subject to rp_filter. Check it here only if the Proxmox host
itself sends or receives multicast. For that case, rp_filter should be 0 or 2
on bridge and bond interfaces; a value of 1 (strict mode) drops multicast
whose source is not reachable back through the receiving interface.

Fix — set rp_filter to loose mode on the affected interfaces:

```
sudo sysctl -w net.ipv4.conf.bond999.rp_filter=2
sudo sysctl -w net.ipv4.conf.vmbr999.rp_filter=2
```

Make persistent in `/etc/sysctl.d/99-multicast.conf`:

```
net.ipv4.conf.bond999.rp_filter=2
net.ipv4.conf.vmbr999.rp_filter=2
```

Apply:

```
sudo sysctl -p /etc/sysctl.d/99-multicast.conf
```

#### Verifying Which Interface Multicast Is Using

Check the routing table decision for the multicast group:

```
ip route get 239.1.1.1
```

Capture IGMP joins on each interface simultaneously in separate terminals:

```
# Terminal 1 — intended multicast interface
sudo tcpdump -i eth1 -nn igmp

# Terminal 2 — competing interface
sudo tcpdump -i eth2 -nn igmp
```

Start the application and observe which terminal shows the IGMP join. If the
join appears on eth2 instead of eth1, the routing table is selecting the wrong
interface. Apply Mechanism 1 or 2 above to correct it.

Verify kernel-level multicast group membership:

```
ip maddr show dev eth1
cat /proc/net/igmp
```

#### Recommendation for This Environment

For Debian guest VMs on Proxmox with multiple NICs where one NIC is the
designated multicast interface for a specific VLAN:

```
1. Add a specific 239.0.0.0/8 route via the correct interface using
   Mechanism 1. Persist it via post-up in /etc/network/interfaces.
   This is the most reliable and least disruptive approach.

2. Always use -i <interface> in mcjoin and -B <group>%<interface> in iperf
   to bind to the correct interface. Belt-and-suspenders with Mechanism 1.

3. Avoid configuring a default gateway on the VLAN data interface.
   A NIC with no gateway does not participate in default route selection
   and will not accidentally win multicast interface selection through
   that mechanism.

4. On the Proxmox host, verify the bridge snooping state matches the
   selected policy (with snooping enabled, check queries, MDB entries
   and router ports), check rp_filter only where the host's own IP
   stack sends or receives the multicast, and inspect all applicable
   bridge-, netdev- and IP-family filtering and Proxmox firewall policy
   before suspecting the guest VM configuration.

5. Use ip route get 239.1.1.1 as the first diagnostic step whenever
   multicast is not reaching its destination on a multi-homed machine.
```

### 3.4 Firewalls and Multicast

Firewalls can block multicast at two points in this design: inside the Debian
guest, and on the Proxmox host when the Proxmox firewall is enabled for the VM.
A firewall that drops multicast causes two different symptoms:

1. **IGMP queries dropped.** The guest kernel must receive the querier's
   general queries to answer them. If they are dropped, the guest joins
   successfully, receives traffic for a few minutes, and then the switch ages
   out its membership (interval depends on configured membership/query timers). See section
   10.4.
2. **Multicast UDP data dropped.** The application receives nothing even
   though tcpdump inside the guest shows the packets. tcpdump sees packets
   before the guest firewall. Do not rely on an established/related rule to admit a new
   unsolicited multicast feed; inspect effective rule counters.

#### Guest Firewall — nftables

Debian 13 uses nftables as its firewall framework. No rules are active by
default unless `nftables.service` is enabled or another tool (ufw, firewalld,
a configuration management baseline) loads rules.

Check what is loaded:

```
sudo nft list ruleset
systemctl is-enabled nftables
```

An empty nftables ruleset does not exclude other host, hypervisor, or network
filters. Inspect the effective path.

If the guest has a default-drop input policy, add rules for IGMP and the
application's UDP ports. Example `/etc/nftables.conf` input chain:

```
table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;
        ct state established,related accept
        iif "lo" accept

        # IGMP queries from the switch querier (IPv4)
        ip protocol igmp accept

        # Multicast application data on VLAN 2601
        iifname "eth1" ip daddr 239.0.0.0/8 udp dport 5001 accept

        # Management access
        iifname "eth0" tcp dport 22 accept
    }
}
```

Apply and enable:

```
sudo nft -c -f /etc/nftables.conf
sudo systemctl enable --now nftables
sudo systemctl reload nftables
```

`nft -c` checks the file without loading it.

#### Guest Firewall — ufw

If the guest uses ufw, allow the multicast data with:

```
sudo ufw allow in on eth1 to 239.0.0.0/8 port 5001 proto udp
```

ufw has no command-line option for IGMP. Add this line to
`/etc/ufw/before.rules`, before the `COMMIT` line of the `*filter` section:

```
-A ufw-before-input -p igmp -j ACCEPT
```

Then reload:

```
sudo ufw reload
```

Do not mix ufw with hand-written nftables rules or direct `iptables` commands.
Use one tool per guest.

#### Proxmox Firewall for the VM

The Proxmox firewall filters a VM's traffic only when all of these are true:

- the firewall is enabled at datacenter level,
- the firewall is enabled in the VM's firewall options,
- the VM NIC has `firewall=1` in its `net0:` line.

Check on the Proxmox host:

```
grep -E '^net[0-9]' /etc/pve/qemu-server/<vmid>.conf
cat /etc/pve/firewall/<vmid>.fw
cat /etc/pve/firewall/cluster.fw
```

If the VM firewall is active with an input policy of DROP, add rules to the
VM's firewall for IGMP and the multicast data, in `/etc/pve/firewall/<vmid>.fw`
or through the GUI (VM → Firewall → Add):

```
[RULES]
IN ACCEPT -p igmp
IN ACCEPT -dest 239.0.0.0/8 -p udp -dport 5001
```

Verify the rules compiled for the VM:

```
pve-firewall status
pve-firewall compile | less
```

With `firewall=1`, Proxmox inserts extra devices between the VM and vmbr999
(`fwbr<vmid>i0`, `fwpr<vmid>p0`, `fwln<vmid>i0`). Captures on `tap<vmid>i0`
still show what the VM sends and receives after filtering. Proxmox VE also
provides an nftables-based firewall implementation (`proxmox-firewall`) as an
option; rules are written in the same `.fw` files either way.

For the host's own filtering of bridged traffic (bridge-, netdev- and, with
`br_netfilter`, IP-family rules), see the host checks in
[3.3](#33-multicast-interface-selection-on-multi-homed-machines).

---

## 4. Debian 13 Guest — Required Packages

### 4.1 Package Overview

| Package     | Purpose                                                          |
|-------------|------------------------------------------------------------------|
| iproute2    | ip command for interface and multicast route management          |
| iputils-ping| ping with multicast support                                      |
| tcpdump     | Packet capture for multicast verification                        |
| mcjoin      | Minimal multicast join and send tool for testing                 |
| iperf       | iperf 2 — network performance tool with multicast UDP support    |
| smcroute    | Static multicast router and group join daemon                    |
| pimd        | PIM-SM multicast routing daemon                                  |
| wireshark   | GUI packet capture (optional, for desktop environments)          |
| tshark      | CLI Wireshark (optional, for headless capture with more detail)  |

Note: install `iperf` (iperf 2), not `iperf3`, for multicast testing. iperf3
does not support multicast.

Note: `iproute2` is installed by default on Debian 13. It is listed here
because the `ip` command is used throughout this guide for multicast
verification and group management.

### 4.2 Installation

Install only the tools needed for the test. The list below excludes optional
routing daemons; installing a daemon package can start a service. Do not start
pimd for this intra-VLAN test:

```
sudo apt update
sudo apt install -y \
    iproute2 \
    iputils-ping \
    tcpdump \
    mcjoin \
    iperf \
    tshark
```

To include the Wireshark GUI (only relevant on desktop environments):

```
sudo apt install -y wireshark
```

During Wireshark installation, when prompted whether non-superusers should
be able to capture packets, select Yes and add your user to the wireshark
group:

```
sudo usermod -aG wireshark $USER
```

Log out and back in for the group change to take effect.

Verify installed versions:

```
mcjoin -v
iperf --version
smcrouted -v
pimd -v
```

---

## 5. Debian 13 Guest — Multicast Receiver Configuration

### 5.1 Joining a Multicast Group Manually

The `ip` command can be used to join a multicast group directly at the kernel
level without any daemon. This is useful for testing whether the network
delivers multicast correctly before configuring applications.

Join a multicast group on a specific interface:

```
sudo ip addr add 239.1.1.1/32 dev eth0 autojoin
```

The `autojoin` flag causes the kernel to send an IGMP join for the group
immediately. The switch should reflect this in its snooping table.

Verify the group is joined:

```
ip maddr show dev eth0
```

Expected output will include the multicast group:

```
2:  eth0
    link  01:00:5e:01:01:01
    inet  239.1.1.1
```

Leave the group:

```
sudo ip addr del 239.1.1.1/32 dev eth0
```

### 5.2 Using mcjoin as a Receiver

mcjoin is a minimal tool designed specifically for multicast testing. It can
join groups and receive traffic with minimal configuration.

Join a group and listen for traffic:

```
mcjoin -i eth0 239.1.1.1
```

Join multiple groups simultaneously:

```
mcjoin -i eth0 239.1.1.1 239.1.1.2 239.1.1.3
```

Join with debug logging (`-v` prints the version; it is not a verbose flag):

```
mcjoin -i eth0 -l debug 239.1.1.1
```

Join on a specific port (for UDP traffic):

```
mcjoin -i eth0 -p 5001 239.1.1.1
```

mcjoin will send an IGMP join for each group specified and listen for UDP
packets. When traffic is received, it prints a count per second. This makes
it straightforward to verify end-to-end delivery without writing application
code.

### 5.3 Using iperf (iperf2) as a Receiver

iperf3 does not support multicast. Use iperf (iperf 2, Debian package `iperf`).

Start an iperf server bound to a multicast group on eth0:

```
iperf -s -u -B 239.1.1.1%eth0 -p 5001 -i 1
```

Parameters:

```
-s                  Server mode (receiver)
-u                  UDP
-B 239.1.1.1%eth0   Bind to the group address and join it on eth0
-p 5001             UDP port to listen on
-i 1                Report every second
```

iperf joins the multicast group when bound to a multicast address. The IGMP
join will be visible in tcpdump and on the switch snooping table. The server
reports loss and jitter per interval.

### 5.4 Using smcroute as a Static Receiver

smcroute can be configured to join multicast groups statically at daemon
startup. This can hold network membership while diagnosing distribution. It does not
replace a receiving application's own socket membership or prove that the
application can read the datagrams.

Install smcroute (if not already installed):

```
sudo apt install -y smcroute
```

Configure smcroute to join groups on startup. Edit the configuration file:

```
sudo nano /etc/smcroute.conf
```

Example configuration to join a group as a receiver on eth0:

```
# Join multicast group 239.1.1.1 on interface eth0
mgroup from eth0 group 239.1.1.1

# Join multiple groups
mgroup from eth0 group 239.1.1.2
mgroup from eth0 group 239.1.1.3
```

The `mgroup` directive causes smcroute to send an IGMP join for the specified
group on the specified interface when the daemon starts. No routing is
performed — this is purely a group join mechanism.

Start smcroute manually to test:

```
sudo smcrouted -f /etc/smcroute.conf -n
```

The `-n` flag runs in the foreground for testing. Remove it for daemon mode.

Verify the group join was sent:

```
sudo tcpdump -i eth0 igmp
```

You should see an IGMP membership report for 239.1.1.1 sent from the VM.

### 5.5 Using pimd as a Dynamic Receiver

pimd is a PIM-SM/SSM routing daemon. It builds multicast routes between
interfaces; it does not join groups on behalf of local applications, and it
has no dense-mode fallback (dense mode is a separate daemon, pimd-dense).
Without a Rendezvous Point, pimd does not route any-source groups such as
239.x.x.x.

In an intra-VLAN environment pimd has no role as a receiver. Use mcjoin,
iperf, smcroute, or the application's own join. See section 7 for when pimd is
appropriate. Running pimd on a VLAN also makes it an IGMP querier candidate on
that VLAN, which can displace the Cisco querier.

---

## 6. Debian 13 Guest — Multicast Sender Configuration

### 6.1 Using mcjoin as a Sender

mcjoin can send multicast traffic as well as receive it. Use the `-s` flag to
enable sender mode.

Send multicast to a group at default rate:

```
mcjoin -i eth0 -s 239.1.1.1
```

Send at a specific packet rate. `-f` sets the interval between packets in
milliseconds, so `-f 100` sends 10 packets per second:

```
mcjoin -i eth0 -s -f 100 239.1.1.1
```

Send with a specific TTL (important for multicast — default TTL of 1 limits
traffic to the local subnet, which is correct for intra-VLAN use):

```
mcjoin -i eth0 -s -t 1 239.1.1.1
```

Send to multiple groups simultaneously:

```
mcjoin -i eth0 -s 239.1.1.1 239.1.1.2
```

The sender does not join the group. A sender does not need to join a group to
send to it. (`-l` sets the log level; mcjoin has no loopback flag.)

### 6.2 Using iperf (iperf2) as a Sender

iperf3 does not support multicast. Use iperf (iperf 2).

Send multicast UDP to a group:

```
iperf -c 239.1.1.1 -u -b 1M -p 5001 -t 30
```

Parameters:

```
-c 239.1.1.1   Send to the multicast group address
-u             UDP mode (required for multicast)
-b 1M          Target bandwidth of 1 Mbit/s
-p 5001        Destination port matching the receiver
-t 30          Run for 30 seconds
```

Bind to a specific source address to ensure traffic exits the correct NIC:

```
iperf -c 239.1.1.1 -u -b 1M -p 5001 -B 192.168.1.10 -t 30
```

Replace `192.168.1.10` with the actual IP address of the VM's interface on
the relevant VLAN.

Set the multicast TTL explicitly:

```
iperf -c 239.1.1.1 -u -b 1M -p 5001 -T 1 -t 30
```

A TTL of 1 limits the traffic to the local subnet, which is correct for
intra-VLAN multicast and prevents unintended propagation if routing is
ever enabled.

### 6.3 Using smcroute for Static Sending

smcroute can install static routes that forward multicast from one interface
to another. It does not originate traffic, so it is not a sender, and in an
intra-VLAN environment it is not needed.

Add a static multicast route between two interfaces:

```
sudo smcroutectl add eth1 192.168.1.20 239.1.1.1 eth2
```

This forwards traffic from source `192.168.1.20` to `239.1.1.1` arriving on
eth1 out of eth2. The outbound interface must differ from the inbound one: the
kernel never forwards a multicast packet back out of the interface it arrived
on, so a route with the same interface in and out does nothing. The sender's
TTL must be greater than 1, because a forwarded packet's TTL is decremented.

This is an advanced, inter-VLAN use case. For basic multicast sending, mcjoin
or iperf is the correct tool.

---

## 7. smcroute vs pimd — Which to Use

### 7.1 smcroute Overview

smcroute is a static multicast routing daemon. It does not participate in any
multicast routing protocol (no PIM, no DVMRP). It manages multicast group
membership and static forwarding rules through a simple configuration file or
runtime commands via smcroutectl.

Strengths:

```
- Simple configuration with no protocol overhead
- Ideal for environments with no inter-VLAN multicast routing
- Group joins are immediate and persistent across daemon restarts
- Low resource usage
- Does not require a Rendezvous Point or PIM neighbors
- Works correctly in intra-VLAN multicast environments
```

Limitations:

```
- No dynamic multicast routing — all groups must be statically configured
- Cannot discover multicast sources automatically
- Not suitable where multicast must be routed dynamically across routed
  boundaries (PIM-SM). smcroute can make static source-specific (SSM) joins
  with `mgroup from <if> group <group> source <source>`
```

### 7.2 pimd Overview

pimd is a full PIM-SM (Protocol Independent Multicast — Sparse Mode) daemon.
It participates in the PIM protocol, discovers neighbors, registers with a
Rendezvous Point, and builds multicast distribution trees dynamically.

Strengths:

```
- Dynamic multicast routing across routed boundaries
- Supports source-specific multicast (SSM) with IGMPv3
- Appropriate for environments with multiple routed segments
- Integrates with Cisco PIM configurations
```

Limitations:

```
- Requires a Rendezvous Point for any-source groups (PIM-SM); SSM groups
  (232.0.0.0/8) do not need one
- No dense-mode fallback; dense mode is a separate daemon (pimd-dense)
- Acts as IGMP querier on enabled interfaces and can take the querier role
  from the Cisco switches
- Significantly more complex to configure and troubleshoot
- Higher resource usage and more control plane traffic
- Overkill for intra-VLAN multicast where no routing is involved
```

### 7.3 Recommendation for This Environment

For intra-VLAN multicast with no inter-VLAN routing and group addresses in the
239.0.0.0/8 range:

```
Use smcroute.
```

Rationale:

- There is no Rendezvous Point in this environment — pimd cannot route
  any-source groups such as 239.x.x.x without one
- All multicast traffic stays within a single VLAN — no routing is needed
- smcroute provides group join functionality with minimal configuration
- smcroute has no protocol overhead and does not generate PIM hellos or
  register messages that could confuse the upstream Cisco switches
- pimd should only be introduced if inter-VLAN multicast routing is added
  in the future and a Rendezvous Point is configured on the Cisco switches

If the application running in the VM handles its own IGMP joins (which most
multicast-aware applications do), neither smcroute nor pimd is needed at the
OS level. smcroute can hold membership for network-path diagnosis, but another socket
should still join explicitly. Depending on accidental wildcard cross-delivery
is not a reliable receiving application design.

---

## 8. systemd Service Configuration

### 8.1 smcroute as a systemd Service

smcroute installs a systemd unit file on Debian. Verify it is present:

```
systemctl status smcroute
```

Enable smcroute to start on boot:

```
sudo systemctl enable smcroute
```

Start smcroute immediately:

```
sudo systemctl start smcroute
```

Configure restart on failure. Edit the service override:

```
sudo systemctl edit smcroute
```

Add the following in the editor that opens:

```
[Service]
Restart=on-failure
RestartSec=5s
```

Save and reload systemd:

```
sudo systemctl daemon-reload
```

Verify the override is applied:

```
systemctl show smcroute | grep -E 'Restart|RestartSec'
```

Verify smcroute is running and has joined the configured groups:

```
sudo smcroutectl show groups
```

View smcroute logs:

```
sudo journalctl -u smcroute -f
```

Full smcroute configuration file example for a VM on VLAN 2601 that needs to
receive multicast groups 239.1.1.1 and 239.1.1.2:

```
# /etc/smcroute.conf
# Join multicast groups on eth0 at daemon startup

mgroup from eth0 group 239.1.1.1
mgroup from eth0 group 239.1.1.2
```

After editing the configuration, restart the service:

```
sudo systemctl restart smcroute
```

### 8.2 pimd as a systemd Service

pimd installs a systemd unit file on Debian. Verify it is present:

```
systemctl status pimd
```

Enable pimd to start on boot:

```
sudo systemctl enable pimd
```

Start pimd immediately:

```
sudo systemctl start pimd
```

Configure restart on failure:

```
sudo systemctl edit pimd
```

Add:

```
[Service]
Restart=on-failure
RestartSec=5s
```

Save and reload:

```
sudo systemctl daemon-reload
```

View pimd logs:

```
sudo journalctl -u pimd -f
```

Optional routed-multicast example only; do not deploy for intra-VLAN reception:

```
# /etc/pimd.conf
# Only for routed (inter-VLAN) multicast. Not used in this environment.
# Enable PIM only on the routed interfaces and name an RP for 239.0.0.0/8.

phyint eth1 enable
phyint eth2 enable
phyint eth0 disable
phyint lo disable

rp-address <RP address> 239.0.0.0/8
```

After editing the configuration, restart the service:

```
sudo systemctl restart pimd
```

Note: pimd has no dense mode. Without an RP it does not route any-source
groups in 239.0.0.0/8 at all. For this intra-VLAN environment, do not run
pimd; see section 7.3.

---

## 9. Testing and Verification

### 9.1 Verification Commands — Proxmox Host

Verify the bridge snooping state matches the selected policy:

```
cat /sys/class/net/vmbr999/bridge/multicast_snooping
```

Expected: the chosen snooping policy (0 for deliberate flooding; 1 for working snooping), not a universal required value.

Verify bridge VLAN membership for a specific tap interface:

```
bridge vlan show dev tap101i0
```

Verify multicast traffic is crossing the bond interface:

```
sudo tcpdump -i bond999 -nn -e multicast -c 50
```

Filter for a specific VLAN and multicast group:

```
sudo tcpdump -i bond999 -nn 'vlan 2601 and host 239.1.1.1'
```

Verify IGMP joins are passing through the bond toward the switch:

```
sudo tcpdump -i bond999 -nn igmp
```

Capture on a specific tap interface:

```
sudo tcpdump -i tap101i0 -nn -e multicast
```

Verify bond member status:

```
cat /proc/net/bonding/bond999
```

### 9.2 Verification Commands — Debian Guest

Verify the interface is up and has an IP address:

```
ip addr show eth0
```

Verify multicast group membership at the OS level:

```
ip maddr show dev eth0
```

Capture all multicast traffic on the interface:

```
sudo tcpdump -i eth0 -nn multicast
```

Capture IGMP traffic specifically:

```
sudo tcpdump -i eth0 -nn igmp
```

Capture traffic for a specific multicast group:

```
sudo tcpdump -i eth0 -nn host 239.1.1.1
```

Show multicast routing table (if smcroute or pimd is running):

```
ip mroute show
```

Check kernel multicast group membership:

```
cat /proc/net/igmp
```

The output shows the interface index, IGMP version, group address (in hex),
and reference count. On x86 the hex value is the address with its bytes
reversed, so 239.1.1.1 appears as `010101EF`. Convert it to verify the correct
group is joined:

```
# Convert hex to dotted decimal
python3 -c "import socket,struct; print(socket.inet_ntoa(struct.pack('<I', 0x010101EF)))"
```

Expected output: `239.1.1.1`.

### 9.3 Worked End-to-End Test Scenario

This scenario tests multicast delivery from a VM on PVE04 VLAN 2601 to a
physical client connected to SWITCH02 Gi1/0/1, also on VLAN 2601.

Environment:

```
Sender:   Debian VM on PVE04, VLAN 2601, IP 192.168.1.10, interface eth0
Receiver: Physical client on SWITCH02 Gi1/0/1, VLAN 2601, IP 192.168.1.20
Group:    239.1.1.1, UDP port 5001
```

**Step 1 — Verify bridge configuration on PVE04**

On PVE04:

```
cat /sys/class/net/vmbr999/bridge/multicast_snooping
```

Expected: the chosen snooping policy (0 for deliberate flooding; 1 for working snooping), not a universal required value.

**Step 2 — Verify IGMP snooping querier on SWITCH01**

On SWITCH01:

```
show ip igmp snooping querier vlan 2601 detail
```

Confirm the querier address is `10.32.204.254` and status is active.

**Step 3 — Start the receiver on the physical client**

On the physical client (VLAN 2601):

```
mcjoin -i eth0 -p 5001 239.1.1.1
```

mcjoin will join the group and wait for traffic. Leave this running.

**Step 4 — Verify the IGMP join reached SWITCH01**

On SWITCH01:

```
show ip igmp snooping groups vlan 2601
```

The physical client's port (arriving via SWITCH02) should appear as a member
of group 239.1.1.1. If the entry is missing, the IGMP join did not reach
SWITCH01. Check SWITCH02's trunk configuration and IGMP snooping querier.

**Step 5 — Verify the IGMP join reached SWITCH02**

On SWITCH02:

```
show ip igmp snooping groups vlan 2601
```

The physical client's port (Gi1/0/1) should appear as a member of 239.1.1.1.
If missing, IGMP snooping on SWITCH02 is not tracking the join correctly.
Verify the querier configuration on SWITCH02.

**Step 6 — Start the sender on the VM**

In the Debian VM on PVE04:

```
mcjoin -i eth0 -s -p 5001 -f 1000 239.1.1.1
```

This sends 1 packet per second to group 239.1.1.1 on port 5001.

**Step 7 — Verify traffic is leaving the VM**

On PVE04, capture on the tap interface for the sender VM:

```
sudo tcpdump -i tap<vmid>i0 -nn host 239.1.1.1
```

You should see UDP packets destined for 239.1.1.1 leaving the tap interface.

**Step 8 — Verify traffic is crossing the bond**

On PVE04:

```
sudo tcpdump -i bond999 -nn 'vlan 2601 and host 239.1.1.1'
```

You should see the multicast frames tagged with VLAN 2601 exiting the bond
toward SWITCH01.

**Step 9 — Verify receipt at the physical client**

On the physical client, the mcjoin receiver's packet count for 239.1.1.1
should rise by about one per second.

**Step 10 — Verify the sender VM appears in the switch snooping table**

On SWITCH01:

```
show ip igmp snooping groups vlan 2601
```

The port connected to PVE04 (Po4) should now show membership for 239.1.1.1
because the receiver on the physical client sent an IGMP join. The sender VM
itself does not need to join the group to send — only receivers join.

**Expected successful flow:**

```
VM sends UDP to 239.1.1.1
    ↓ tap101i0 (multicast frame exits VM)
    ↓ vmbr999 (flooded to bond999, or via its learned router port with snooping)
    ↓ bond999 (LACP bond delivers to SWITCH01 Po4)
    ↓ SWITCH01 (IGMP snooping table shows Po4 as receiver for 239.1.1.1)
    ↓ SWITCH01 forwards to SWITCH02 trunk (Gi1/0/46)
    ↓ SWITCH02 (IGMP snooping table shows Gi1/0/1 as receiver for 239.1.1.1)
    ↓ SWITCH02 forwards to Gi1/0/1
    ↓ Physical client receives multicast packet
```

---

## 10. Troubleshooting

### 10.1 Multicast Not Leaving the VM

Symptom: tcpdump on the VM's eth0 shows no outbound multicast traffic when
the sending application is running.

Step 1 — Verify the interface is up:

```
ip link show eth0
```

The interface must show `UP` and `LOWER_UP`.

Step 2 — Verify the interface has an IP address:

```
ip addr show eth0
```

Multicast senders need a source IP address. Without one, the kernel may drop
outbound multicast silently.

Step 3 — Verify the multicast route exists in the kernel:

```
ip route show table all | grep 239
```

If no route exists for the multicast range, add a default multicast route:

```
sudo ip route add 239.0.0.0/8 dev eth0
```

Step 4 — Verify the application is binding to the correct interface. Some
multicast applications bind to a specific interface by IP address. If the
application binds to `0.0.0.0`, it may exit via the wrong interface. Use the
interface-specific bind option in the application (e.g. `-B <ip>` in iperf,
`-i <interface>` in mcjoin).

Step 5 — Check the multicast TTL. A TTL of 0 means the packet is not
forwarded beyond the originating socket. Verify the application is setting
TTL to at least 1.

### 10.2 Multicast Not Arriving at the VM

Symptom: The physical client is sending multicast, tcpdump on the bond999
interface shows the traffic arriving, but the VM's eth0 shows nothing.

Step 1 — Verify the bridge snooping state matches the selected policy:

```
cat /sys/class/net/vmbr999/bridge/multicast_snooping
```

A value of `1` is valid for a working-snooping policy and is not by itself the
fault. With snooping enabled, check that queries reach the bridge on VLAN 2601,
that the VM's tap port appears in the MDB for the group, and that the uplink is
a router port:

```
sudo tcpdump -i bond999 -nn -e -c 20 igmp
bridge -d mdb show dev vmbr999
bridge vlan show
```

If the tap port is missing from the MDB, diagnose the querier, the VM's
reports and the VLAN path. Switching to `bridge-mcsnooping 0` is a deliberate
flooding policy choice ([2.2](#22-bridge-mcsnooping-behavior)), not the default
repair.

Step 2 — Verify the VM NIC VLAN tag matches the traffic VLAN:

```
cat /etc/pve/qemu-server/<vmid>.conf | grep net
```

The `tag=` value must match the VLAN the multicast traffic is on.

Step 3 — Capture on the tap interface:

```
sudo tcpdump -i tap<vmid>i0 -nn multicast
```

If traffic appears on the tap but not inside the VM, the issue is within the
guest OS (interface down, firewall, application not listening).

Step 4 — Verify no firewall is dropping multicast inside the VM. Inspect the
complete ruleset, chain policies and counters (a grep for "multi" or a group
address misses default drops, sets and interface rules):

```
sudo nft -a list ruleset
sudo iptables -S
```

If the guest firewall drops the traffic, add a scoped rule for IGMP and for
the group and UDP port on the data interface in the guest's own firewall
manager (nftables or ufw), as in
[3.4](#34-firewalls-and-multicast). Do not insert a broad `iptables ACCEPT`
alongside a managed ruleset.

### 10.3 IGMP Join Not Seen by Switch

Symptom: The VM has joined a group but `show ip igmp snooping groups vlan 2601`
on SWITCH01 does not show the VM's port.

Step 1 — Verify the IGMP join is being sent by the VM:

```
sudo tcpdump -i eth0 -nn igmp
```

You should see an IGMP membership report. If not, the VM has not actually
joined the group. Verify smcroute is running or the application has called
the join.

Step 2 — Verify the join is crossing the bond:

```
sudo tcpdump -i bond999 -nn igmp
```

Step 3 — If Step 1 showed the VM's report but Step 2 did not, inspect the
bridge path. With snooping enabled, check the snooping state, MDB and router
ports (`bridge -d mdb show dev vmbr999`), the tap and bond VLAN membership
(`bridge vlan show`), and bridge-family filtering (see the Proxmox host checks in
[3.3](#33-multicast-interface-selection-on-multi-homed-machines)). Treat disabling snooping as a deliberate policy change, not a
first response.

Step 4 — Verify the VLAN tag on the IGMP join frame matches the expected VLAN:

```
sudo tcpdump -i bond999 -nn -e igmp
```

The frame should show VLAN 2601 in the 802.1Q tag. If the tag is missing or
wrong, the VM NIC configuration does not match.

### 10.4 Multicast Works Briefly Then Stops

Symptom: Multicast delivery works after joining but stops after 60–300 seconds.

A common hypothesis is membership aging without query refresh: the querier is
not active, or its queries or the VM's reports are not crossing the path. Other
candidates include querier or snooping state changes, the application leaving
the group, and bridge snooping state on vmbr999. Correlate local joins, captures
spanning complete query intervals, and switch and bridge state before settling
on a cause.

Step 1 — Verify the querier is active on SWITCH01:

```
show ip igmp snooping querier vlan 2601 detail
```

Step 2 — Verify IGMP queries are arriving at the VM:

```
sudo tcpdump -i eth0 -nn igmp
```

You should see periodic IGMP general queries arriving from the switch querier
address (10.32.204.254). If no queries arrive, the querier is not functioning
or VLAN tagging is preventing delivery.

Step 3 — Verify the join is still held. The kernel answers IGMP queries for
groups held by an open socket, such as those smcroute opens for `mgroup`
lines. If smcroute (or the application holding the join) has crashed or been
stopped, the socket is closed, queries go unanswered, and membership times
out.

```
systemctl status smcroute
```

Step 4 — Check the IGMP membership interval. An illustrative query interval is
125 seconds with a computed membership interval of 260 seconds
(robustness 2 × 125 s query interval + 10 s maximum response time). If the
querier is sending queries but the VM is not responding, the switch will
remove the entry after 260 seconds. Also check that no firewall inside the VM
drops incoming IGMP: tcpdump shows queries before the firewall, so queries
visible in tcpdump with no report in reply point to a firewall rule in the
guest or in the Proxmox VM firewall (section 3.4).

### 10.5 Bridge Delivering Multicast to Wrong VMs

Symptom: A VM on VLAN 2602 is receiving multicast traffic intended for VLAN
2601.

This should not occur with a properly configured VLAN-aware bridge. If it does:

Step 1 — Verify each VM NIC has the correct VLAN tag:

```
cat /etc/pve/qemu-server/<vmid>.conf | grep net
```

A VM with no tag or the wrong tag may be receiving unintended traffic.

Step 2 — Verify the bridge is VLAN-aware:

```
bridge vlan show
```

Each tap interface should only be a member of its configured VLAN.

Step 3 — Verify bridge-pvid is set to 999 (the native VLAN) and that no
untagged traffic is landing on the wrong VLAN:

```
bridge vlan show dev bond999
```

The bond999 interface should show all allowed VLANs with the PVID set to 999.

### 10.6 Multicast Reaches the VM but Not the Application

Symptom: tcpdump on eth1 inside the guest shows the group traffic, but the
application (or mcjoin/iperf) receives nothing or reports loss.

tcpdump sees packets before the guest firewall, rp_filter, and socket delivery,
so the drop is inside the guest.

Step 1 — Check the guest firewall (section 3.4):

```
sudo nft list ruleset
```

If a default-drop input policy has no rule for the UDP port, add one.

Step 2 — Check rp_filter (section 11.3):

```
sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.eth1.rp_filter
nstat -az TcpExtIPReversePathFilter
```

A rising counter means reverse-path drops.

Step 3 — Check the application joined on eth1 and listens on the right port:

```
ip maddr show dev eth1
ss -uamnp | grep 5001
```

Step 4 — Check for socket buffer drops at high rates (section 11.8):

```
nstat -az UdpRcvbufErrors
```

Step 5 — If another multicast application in the guest uses the same port,
check for cross-delivery (section 11.8, IP_MULTICAST_ALL).

### 10.7 Multicast Interrupted After Live Migration

Symptom: a VM stops receiving multicast after it is live-migrated to another
Proxmox host, and recovers on its own within about two minutes.

After migration the VM's traffic enters the network through the new host's
bond and a different SWITCH01 port-channel. QEMU announces the VM's MAC on the
new host, so unicast recovers immediately, but the switch's IGMP snooping table
still lists the old host's port-channel for the VM's groups. Delivery resumes
when the next general query arrives and the VM reports again through the new
host (up to one query interval, 125 seconds by default).

Options to reduce the gap:

- Lower the IGMP query interval on the SWITCH01 querier for VLAN 2601.
- Have the application or smcroute re-join after migration. For smcroute:
  `sudo systemctl restart smcroute` inside the guest sends fresh reports
  immediately.

Verify recovery timing by running mcjoin as a receiver in the VM during a test
migration and noting when the packet count resumes. On SWITCH01,
`show ip igmp snooping groups vlan 2601` shows which port-channel holds the
membership before and after.

---

## 11. Deep Dive — Advanced Multicast Interface Control (Debian Guest VMs)

This section covers kernel mechanisms for controlling multicast interface
selection and behavior on Debian guest VMs. It goes beyond the operational
configuration in sections 1–10 and is a reference for complex multi-homed
designs and hard-to-diagnose failures.

The topics apply primarily to Debian guest VMs. Where a topic also affects the
Proxmox host (bond999, vmbr999), this is noted explicitly.

Examples use the multi-homed guest from section 3.3:

```
eth0 — management, IP 10.32.200.x,  gateway 10.32.200.254
eth1 — VLAN 2601,  IP 192.168.1.10, no gateway
```

Persistent examples use `/etc/network/interfaces` (ifupdown), as elsewhere in
this guide. If a guest uses systemd-networkd instead, the equivalent settings
are `[Route]` and `[RoutingPolicyRule]` sections in the interface's `.network`
file; see `man systemd.network`.

### 11.1 Policy Routing with ip rule

Policy routing lets the kernel choose a routing table based on more than the
destination: source address, incoming interface, firewall mark, and others.
Rules are evaluated in priority order before the `main` table.

Show rules and tables:

```
ip rule show
ip route show table all
```

The default rules are:

```
0:      from all lookup local
32766:  from all lookup main
32767:  from all lookup default
```

**How rules apply to multicast.** For multicast sends, the kernel's route lookup
includes the source address if the socket has one (from `bind()` or from
`IP_MULTICAST_IF` given as an address). A `from 192.168.1.10` rule therefore
matches traffic from a sender bound to that address, such as
`iperf -c ... -B 192.168.1.10`.

The IGMP join is different. When an application joins without naming an
interface, the kernel looks up the group address with no source address. A
`from` rule never matches that lookup. For applications relying on default membership-interface selection, inspect
the applicable lookup and add a scoped route only if needed. Applications that
name the membership interface explicitly do not require a blanket 239/8 route.

**Example: a dedicated table for VLAN 2601.**

Optionally name the table (numbers work without a name):

```
echo '2601 vlan2601' | sudo tee /etc/iproute2/rt_tables.d/multicast.conf
```

Add the routes and rule at runtime to test:

```
sudo ip route add 192.168.1.0/24 dev eth1 table 2601
sudo ip route add 239.0.0.0/8 dev eth1 table 2601
sudo ip rule add priority 100 from 192.168.1.10 table 2601
```

Persist in `/etc/network/interfaces`, alongside the main-table route from
section 3.3:

```
auto eth1
iface eth1 inet static
    address 192.168.1.10/24
    post-up ip route add 239.0.0.0/8 dev eth1
    post-up ip route add 192.168.1.0/24 dev eth1 table 2601
    post-up ip route add 239.0.0.0/8 dev eth1 table 2601
    post-up ip rule add priority 100 from 192.168.1.10 table 2601
    pre-down ip rule del priority 100 from 192.168.1.10 table 2601
    pre-down ip route flush table 2601
    pre-down ip route del 239.0.0.0/8 dev eth1
```

Verify:

```
ip rule show
ip route show table 2601
ip route get 239.1.1.1 from 192.168.1.10
```

**Example: marking traffic for one application.** If an application cannot bind
to a source address, mark its packets with nftables (by cgroup or UID) and route
by mark (`ip rule add fwmark 0x2601 table 2601`). This is complex and rarely
needed; prefer binding in the application.

**Interaction with rp_filter.** In strict mode, rp_filter checks the reverse
path using the full policy routing decision, as if replying from the receiving
interface. A rule that routes the sender's subnet through a different table can
make strict mode pass or fail unexpectedly. Test with:

```
ip route get 192.168.1.20 from 192.168.1.10 iif eth1
```

A result with `dev eth1` passes strict reverse-path filtering.

**Proxmox host.** Policy routing on the host affects only the host's own
traffic (management, cluster, storage). It has no effect on VM traffic bridged
through vmbr999.

### 11.2 Multicast Routing Tables

The kernel keeps multicast forwarding state separate from the unicast routing
table. It is used only when a multicast routing daemon (smcroute with `mroute`
entries, or pimd) is running. Group joins and ordinary multicast send/receive do
not use it.

Components:

```
VIF table       Virtual interfaces the daemon has registered for forwarding.
                /proc/net/ip_mr_vif
MFC             Multicast Forwarding Cache: (source, group, inbound VIF) →
                list of outbound VIFs with TTL thresholds.
                /proc/net/ip_mr_cache
```

Show forwarding entries in readable form:

```
ip mroute show
```

Example:

```
(192.168.1.20,239.1.1.1)  Iif: eth1  Oifs: eth2  State: resolved
```

Rules the kernel applies when forwarding:

- A packet is forwarded only if it arrives on the entry's inbound interface.
  Packets arriving elsewhere are not forwarded (pimd treats them as an RPF
  failure).
- A packet is never forwarded back out of its inbound interface.
- Each outbound VIF has a TTL threshold. A packet is forwarded only if its TTL
  is greater than the threshold, and the TTL is decremented on forwarding.
  Senders with TTL 1 are never forwarded.
- If no MFC entry matches, the kernel notifies the daemon (an "upcall"). pimd
  may then create an entry. smcroute creates entries for wildcard-source
  `mroute` lines on demand.

`net.ipv4.conf.all.mc_forwarding` reads `1` while a daemon holds the multicast
routing socket. It is read-only and set by the kernel.

Only one process can own the multicast routing socket for a routing table.
Starting pimd while smcroute is running (or the reverse) fails with an
"address in use" error in the log. Linux supports multiple multicast routing
tables (one per VRF, for example) for separate daemon instances; check that the
running kernel has `CONFIG_IP_MROUTE_MULTIPLE_TABLES` before relying on it:

```
grep IP_MROUTE /boot/config-$(uname -r)
```

**Interaction with IGMP snooping.** The MFC decides which interfaces a routed
packet leaves on. Snooping (on the Cisco switches, or on vmbr999 if
bridge-mcsnooping were enabled) decides which ports within a VLAN receive it.
They are independent: an MFC entry forwarding into VLAN 2602 still needs a
receiver's join on VLAN 2602 for the switch to deliver the traffic to that
receiver's port.

In this intra-VLAN environment the MFC is empty and should stay empty, on both
guests and Proxmox hosts. A non-empty `ip mroute show` on a system that is not
meant to route multicast means a routing daemon is running that should not be.

### 11.3 rp_filter — Reverse Path Filtering

Reverse path filtering drops a received IPv4 packet if the packet's source
address is not reachable back through the interface it arrived on. It applies to
multicast data the same way as to unicast. It is a frequent cause of
"tcpdump shows the traffic but the application gets nothing" on multi-homed
guests.

It applies only to packets received by a machine's own IP stack. Frames bridged
by the Proxmox host between tap interfaces and bond999 are not subject to the
host's rp_filter.

Values:

| Value | Mode   | Check                                                              |
|-------|--------|--------------------------------------------------------------------|
| 0     | Off    | No check                                                           |
| 1     | Strict | The best route back to the source must use the receiving interface |
| 2     | Loose  | The source must be reachable through any interface                 |

**The effective value is the higher of `net.ipv4.conf.all.rp_filter` and
`net.ipv4.conf.<interface>.rp_filter`.** Setting the interface to 2 makes it
loose whatever `all` is. With interface=1, all=0 keeps strict mode,
whereas all=2 makes the effective mode loose. Setting only the interface to 0
cannot disable filtering when all remains nonzero.

Check every value on the system:

```
sysctl -a 2>/dev/null | grep '\.rp_filter'
```

Do not assume a default. The value can come from the kernel, from systemd's
`/usr/lib/sysctl.d/` files, from `/etc/sysctl.d/`, or from a hardening
baseline. Read it on each system.

**How strict mode breaks multicast.** The sender 192.168.1.20 is on VLAN 2601.
If the guest's route to 192.168.1.0/24 is via eth1, strict mode passes. It
fails when:

- The sender is on another subnet (routed multicast) and the route back to it
  is via eth0's default route.
- The sender's source address is outside the subnet configured on eth1 (for
  example a device with a misconfigured or link-local source address).
- Policy routing sends the reply path through another table (section 11.1).

Count drops:

```
nstat -az TcpExtIPReversePathFilter
```

(The counter is named `TcpExt…` for historical reasons but counts all IPv4
reverse-path drops.)

Log dropped packets (noisy; enable only while diagnosing):

```
sudo sysctl -w net.ipv4.conf.all.log_martians=1
sudo journalctl -k -f | grep -i martian
```

**Fix — loose mode on the multicast interface.** Persist in
`/etc/sysctl.d/99-multicast.conf`:

```
net.ipv4.conf.eth1.rp_filter = 2
```

Apply:

```
sudo sysctl -p /etc/sysctl.d/99-multicast.conf
```

Because the higher value wins, this works whether `all` is 0, 1 or 2. Do not
set the interface to 0 to disable the check: if `all` is 1, the effective value
stays 1.

**VLAN interfaces with a dot in the name.** In sysctl keys the dot is the
separator, so an interface named `eth1.2601` is written with a slash:

```
sysctl net.ipv4.conf.eth1/2601.rp_filter
```

Use the same slash form in files under `/etc/sysctl.d/`. A per-interface key
applies only once the interface exists; systemd reapplies matching keys when
an interface appears, but verify after reboot.

**Proxmox host.** The values on bond999 and vmbr999 matter only for traffic the
host itself sends or receives (section 3.3). For VM traffic, check rp_filter
inside the guest.


### 11.4 igmp_max_memberships — Host and Guest Limits

`net.ipv4.igmp_max_memberships` limits how many groups **one socket** can join.
The default is 20. A join beyond the limit fails with `ENOBUFS`
("No buffer space available"), which applications often report misleadingly as
a memory problem.

It is a per-socket limit inside each guest. It is not a host-wide or
bridge-wide limit, and VM joins passing through the Proxmox bridge do not count
against the host's value.

Related limits:

| Setting                                   | Default | Limits                                                    |
|-------------------------------------------|---------|-----------------------------------------------------------|
| net.ipv4.igmp_max_memberships             | 20      | Groups per IPv4 socket                                    |
| net.ipv4.igmp_max_msf                     | 10      | Sources per IPv4 source filter (SSM include/exclude list) |
| /sys/class/net/vmbr999/bridge/multicast_hash_max | kernel default | Groups the bridge can track while snooping   |

There is no host-wide group limit in the kernel: many sockets can each join up
to the per-socket limit. Host-wide limits come from elsewhere:

- **The guest NIC's multicast filter.** When a NIC runs out of filter slots the
  driver puts it in all-multicast mode. This is correct but costs CPU. Check
  with `ip -d link show eth1` (look for `ALLMULTI`).
- **The Proxmox bridge's snooping table** (`multicast_hash_max`). It applies
  only while snooping is on. With `bridge-mcsnooping 0` (the flooding
  policy shown in section 2.3), the bridge tracks no groups and this limit
  cannot be hit.
- **The Cisco switches' IGMP snooping table.** See the
  [Cisco guide](MulticastReference-Cisco_r1.0.0.md).

Raise the per-socket limit when one application must join many groups. Persist
in `/etc/sysctl.d/99-multicast.conf`:

```
net.ipv4.igmp_max_memberships = 256
```

Apply with `sudo sysctl -p /etc/sysctl.d/99-multicast.conf`. Already-open
sockets keep working; new joins use the new limit.

Check what is joined per interface:

```
ip maddr show
cat /proc/net/igmp
```

### 11.5 VRFs — Virtual Routing and Forwarding

A VRF is a Linux device with its own routing table. Interfaces enslaved to the
VRF use that table, isolated from the `main` table. VRFs are not used in this
environment; this subsection explains when and how they would be.

Benefits in a multicast context:

```
- Interface selection is unambiguous: a socket bound to the VRF can only
  use VRF interfaces, so the management default route cannot capture
  multicast joins or sends
- The same group can be used independently in two VRFs
- Separate multicast routing daemons per VRF (with multiple-table support)
- Fewer rp_filter surprises, since the VRF table contains only data routes
```

Costs:

```
- Every application must be started inside the VRF or bind to it
- Management tools (ssh, monitoring) stay in the default VRF and cannot reach
  VRF networks without route leaking
- More moving parts to troubleshoot
```

Create a VRF at runtime and move eth1 into it:

```
sudo ip link add vrf-mc type vrf table 1001
sudo ip link set vrf-mc up
sudo ip link set eth1 master vrf-mc
sudo ip route add 239.0.0.0/8 dev eth1 table 1001
```

Moving an interface into a VRF moves its connected routes into the VRF's table.
Routes added earlier in `main` for that interface (such as the 239.0.0.0/8 route
from section 3.3) are not moved; add them to table 1001.

Persist in `/etc/network/interfaces` (classic ifupdown):

```
auto vrf-mc
iface vrf-mc inet manual
    pre-up ip link add vrf-mc type vrf table 1001
    up ip link set vrf-mc up
    post-down ip link del vrf-mc

auto eth1
iface eth1 inet static
    address 192.168.1.10/24
    pre-up ip link set eth1 master vrf-mc
    post-up ip route add 239.0.0.0/8 dev eth1 table 1001
```

ifupdown2 (used on Proxmox hosts and available for guests) supports VRFs
natively with `vrf-table 1001` on the VRF stanza and `vrf vrf-mc` on member
interfaces.

Verify:

```
ip -d link show vrf-mc
ip route show vrf vrf-mc
ip route get vrf vrf-mc 239.1.1.1
```

Run a tool inside the VRF:

```
sudo ip vrf exec vrf-mc mcjoin -i eth1 -p 5001 239.1.1.1
```

`ip vrf exec` attaches a BPF program to a cgroup and needs cgroup v2, which is
the default on Debian 12 and 13.

Applications can instead bind their socket to the VRF device with
`SO_BINDTODEVICE`. For unbound UDP sockets in the default VRF to receive
packets that arrive on VRF interfaces, set:

```
net.ipv4.udp_l3mdev_accept = 1
```

Only do this if that cross-VRF receive is intended.

Run smcroute for VRF interfaces with the service's command wrapped in
`ip vrf exec vrf-mc` (a `systemctl edit smcroute` override of `ExecStart=`), so
its `mgroup` sockets belong to the VRF. For forwarding (`mroute`) inside a VRF,
the daemon must use the VRF's multicast routing table, which needs
multiple-table support (section 11.2) and daemon support; test before relying
on it.

**Proxmox host.** VRFs on the host do not isolate VM traffic, which is bridged,
not routed. Isolate VM multicast with VLANs on vmbr999 (section 2.4).

### 11.6 smcroute Interface Binding in Multi-Interface Environments

`mgroup` and `mroute` lines always name their interfaces explicitly. smcroute
does not use the routing table to choose an interface. A join on the wrong
interface is a silent configuration error: smcroute logs no error, and the IGMP
report simply appears on that interface.

Join the same group on two interfaces (two VLANs) — one line per interface:

```
mgroup from eth1 group 239.1.1.1
mgroup from eth2 group 239.1.1.1
```

Source-specific join:

```
mgroup from eth1 group 239.1.1.4 source 192.168.1.20
```

Interfaces that do not exist at startup are skipped with a log message. If an
interface comes up later, reload smcroute to retry the joins:

```
sudo systemctl reload smcroute
```

Debian's smcroute unit starts after the network is configured, but an interface
that depends on DHCP or is created late can still miss the startup joins.

Verify where each group is joined:

```
sudo smcroutectl show groups
ip maddr show dev eth1
ip maddr show dev eth2
```

Interaction with the 239.0.0.0/8 route from section 3.3: none for `mgroup`. The
route affects only applications that do not name an interface. A guest with
both can therefore join a group on eth2 through smcroute while an application's
own unnamed join of the same group goes out eth1. Name interfaces everywhere.

### 11.7 pimd Interface Binding in Multi-Interface Environments

pimd enables PIM and IGMP on every multicast-capable interface unless told
otherwise. On an enabled interface it:

- sends PIM hello messages every 30 seconds,
- runs as an IGMP querier and takes part in the querier election.

IGMP querier election is won by the **lowest IP address** on the segment. If
pimd's address on a VLAN is lower than the Cisco querier's address
(10.32.204.254 for VLAN 2601), pimd becomes the querier for that VLAN. A host
holding the querier role is a common cause of intermittent multicast loss:
when it restarts or is patched, queries stop until the switch takes the role
back, and memberships can time out in the meantime.

Disable every interface that should not run PIM, and enable only the routed
multicast interfaces:

```
phyint eth0 disable
phyint eth1 enable
phyint eth2 enable
phyint lo disable
```

Newer pimd versions also support a global `no phyint` directive to start with
all interfaces disabled; check `man pimd.conf` for the installed version.

Interaction with rp_filter: pimd does its own RPF check against the unicast
routing table to choose the inbound interface for each source. If kernel
rp_filter is strict and the unicast route back to a source points at a
different interface, the kernel drops packets before pimd sees them. Use loose
mode (section 11.3) on PIM interfaces.

Verify pimd's interface state with `pimctl`, if the installed pimd version
ships it:

```
sudo pimctl show interface
sudo pimctl show neighbor
sudo pimctl show igmp
```

Otherwise, run pimd in the foreground with debug output:

```
sudo pimd -n -d
```

Never run pimd on a Proxmox host's vmbr999 or bond999: it would become a PIM
router and querier candidate on every VLAN the bridge carries.

### 11.8 Socket-Level Controls — IP_MULTICAST_ALL and Receive Buffers

Two socket-level behaviors cause hard-to-diagnose problems in receivers that
bind to a port rather than to a group.

**IP_MULTICAST_ALL.** Linux enables this socket option by default. A UDP socket
bound to `0.0.0.0:5001` then receives traffic for **every** group joined by
**any** socket on the host on port 5001 — not only the groups it joined itself.
Two applications in one guest that use the same port for different groups
receive each other's traffic.

Mitigations, in order of preference:

1. The application binds to the group address (`239.1.1.1:5001`) instead of
   `0.0.0.0:5001`.
2. The application sets `IP_MULTICAST_ALL` to 0 on its socket
   (this guide qualifies only the IPv4 setting).
3. Use different ports for different groups.

There is no system-wide sysctl for this option.

**Receive buffers.** A socket's receive buffer absorbs bursts while the
application is busy. If it fills, the kernel drops packets and increments
`UdpRcvbufErrors`:

```
nstat -az UdpRcvbufErrors Udp6RcvbufErrors
```

A rising count with traffic visible in tcpdump means drops are local to the
guest.

An application's requested buffer size (`SO_RCVBUF`) is silently capped at
`net.core.rmem_max`. Check the current limits:

```
sysctl net.core.rmem_max net.core.rmem_default
```

Raise the cap for high-rate multicast receivers. Persist in
`/etc/sysctl.d/99-multicast.conf`:

```
net.core.rmem_max = 16777216
```

The kernel doubles the value an application requests (to account for overhead)
and reports the doubled value back. Per-socket drop and memory counters are
shown by:

```
ss -uamn
```

The `skmem:(…d<N>)` field is the drop count for each socket.

**Proxmox host.** High-rate multicast can also be dropped before it reaches the
guest: on the tap interface's queue or in the VM's virtio-net queues when the
VM's vCPUs are busy. Compare `ip -s link show tap<vmid>i0` on the host (TX
drops toward the VM) with the guest's counters. Enabling multiqueue on the VM
NIC (`queues=` in the `net0:` line) spreads receive load across vCPUs.

### 11.9 Deep Dive Troubleshooting

Failures that occur only when the mechanisms in sections 11.1–11.8 are in use.
Basic troubleshooting for standard configurations is in section 10.

**Policy routing sends joins out the wrong interface.**
Symptom: sends from the bound source address go out eth1, but the IGMP join for
a receiver goes out eth0.
Cause: `from` rules do not match the join lookup (section 11.1).
Check: `ip route get 239.1.1.1` (no `from`).
Fix: keep 239.0.0.0/8 in the `main` table, or have the application name the
interface in its join.

**Stale or unexpected MFC entries.**
Symptom: multicast is duplicated onto another VLAN, or a guest forwards traffic
it should not.
Check: `ip mroute show` and `systemctl status smcroute pimd`.
Fix: remove the unintended `mroute` lines or stop the routing daemon. On a
system that should not route multicast, the MFC must be empty.

**rp_filter drops with no obvious log entry.**
Symptom: traffic in tcpdump, nothing in the application, firewall correct.
Check: `nstat -az TcpExtIPReversePathFilter` rising; effective value =
max(`all`, interface).
Fix: loose mode (section 11.3), or fix the unicast route to the sender's
subnet.

**igmp_max_memberships exhausted.**
Symptom: the first 20 groups work; later joins fail with "No buffer space
available" (ENOBUFS) in the application log, while other applications still
join fine.
Check: count the groups the application joins per socket.
Fix: raise `net.ipv4.igmp_max_memberships` (section 11.4) and restart the
application.

**smcroute joined on the wrong interface.**
Symptom: `smcroutectl show groups` lists the group, but the switch has no
membership on VLAN 2601.
Check: `ip maddr show` on each interface; `tcpdump -nn igmp` on each.
Fix: correct the `from <interface>` in `/etc/smcroute.conf` and reload.

**smcroute joins missing after boot.**
Symptom: joins work after `systemctl restart smcroute` but not after reboot.
Cause: the daemon started before the interface existed.
Fix: make the interface `auto` in `/etc/network/interfaces` so it is up before
`network-online.target`, or reload smcroute from a `post-up` line on that
interface.

**pimd took over the querier role.**
Symptom: intermittent multicast loss that coincides with pimd restarts or guest
reboots; `show ip igmp snooping querier vlan <id>` on SWITCH01 shows the guest's
address.
Fix: `phyint <interface> disable` for every interface that is not a PIM
interface (section 11.7).

**VRF application cannot join or receive.**
Symptom: the application works outside the VRF but not when the interface is
moved into it.
Check: is the application running under `ip vrf exec` or bound to the VRF
device? Does `ip route get vrf vrf-mc 239.1.1.1` show the expected interface?
Fix: start the application in the VRF; add the 239.0.0.0/8 route to the VRF
table; set `udp_l3mdev_accept` only if cross-VRF receive is intended.

**Two applications receive each other's groups.**
Symptom: an application reports unexpected packets or parse errors after another
multicast application starts in the same guest.
Cause: `IP_MULTICAST_ALL` with sockets bound to `0.0.0.0` on the same port
(section 11.8).
Fix: bind to the group address, disable the option in the application, or use
distinct ports.

**Receive drops at high rate.**
Symptom: loss reported by the application or iperf server; the switch and
tcpdump on the bond show complete traffic.
Check: `nstat -az UdpRcvbufErrors` and `ss -uamn` in the guest;
`ip -s link show tap<vmid>i0` on the Proxmox host.
Fix: raise `rmem_max` and the application's buffer request (section 11.8);
enable VM NIC multiqueue; check the VM's CPU load.

---

## 12. Glossary

| Term                 | Definition                                                                    |
|----------------------|-------------------------------------------------------------------------------|
| bond999              | LACP 802.3ad bonded interface on PVE hosts providing uplink to SWITCH01.      |
| bridge-fd            | Bridge forward delay. Set to 0 to prevent forwarding delays on tap up events. |
| bridge-mcsnooping    | Linux bridge option controlling IGMP snooping. 0 = disabled (transparent).   |
| bridge-pvid          | Port VLAN ID. The native/untagged VLAN for the bridge uplink port.            |
| bridge-vlan-aware    | Enables per-VLAN forwarding on the Linux bridge.                              |
| bridge-vids          | The set of VLANs the bridge carries.                                          |
| IP_MULTICAST_ALL     | Socket option (on by default) delivering all joined groups on a port to wildcard-bound sockets. |
| IGMP                 | Internet Group Management Protocol. Used by hosts to join multicast groups.   |
| IGMP Snooping        | Switch or bridge feature tracking multicast group membership per port.        |
| igmp_max_memberships | Kernel parameter controlling max multicast groups per socket. Default 20.     |
| iperf (iperf2)       | Network performance testing tool with multicast UDP support.                  |
| iperf3               | Network performance testing tool. Does not support multicast.                 |
| ip maddr             | Linux command showing multicast group memberships per interface.               |
| ip route get         | Linux command showing which interface and route the kernel selects for a dest. |
| ip rule              | Linux command managing policy routing rules evaluated before the main table.  |
| Intra-VLAN           | Traffic within a single VLAN requiring no routing.                            |
| mcjoin               | Minimal multicast join and send tool for testing.                             |
| MFC                  | Multicast Forwarding Cache. Kernel table controlling multicast frame forwarding.|
| Multi-homed          | A machine with more than one active network interface.                        |
| nftables             | Linux packet filtering framework; Debian 13's default firewall backend.       |
| pimd                 | PIM-SM multicast routing daemon. For routed multicast environments.           |
| PIM-SM               | Protocol Independent Multicast Sparse Mode. Routing protocol for multicast.   |
| Proxmox VE           | Open-source hypervisor platform based on Debian Linux.                        |
| Proxmox firewall     | Per-datacenter/host/VM firewall managed in /etc/pve/firewall/*.fw.            |
| rp_filter            | Reverse path filtering. Kernel feature that drops packets with asymmetric paths.|
| smcroute             | Static multicast routing daemon. For intra-VLAN multicast environments.       |
| tap interface        | Virtual network interface connecting a VM to the Linux bridge.                |
| tcpdump              | Command-line packet capture tool.                                             |
| tshark               | Command-line Wireshark for detailed packet capture and dissection.            |
| ufw                  | Uncomplicated Firewall; a simplified front end to the Linux firewall.        |
| vmbr999              | The VLAN-aware Linux bridge on PVE hosts connecting VMs to the network.       |
| VRF                  | Virtual Routing and Forwarding. Isolated routing table bound to interfaces.   |
| 239.0.0.0/8          | Administratively scoped multicast range. Administratively scoped; configured boundaries enforce scope.  |

## Appendix A — Acronyms and meanings

Literal command/API identifiers, interface names and lab device names are not
acronyms. Product names (such as IOS XE, ESXi and VirtIO) identify platforms;
use the vendor documentation for their release-specific behavior.

| Term | Meaning |
|---|---|
| BPDU | Bridge Protocol Data Unit |
| CLI | Command-Line Interface |
| CPU | Central Processing Unit |
| DHCP | Dynamic Host Configuration Protocol |
| GUI | Graphical User Interface |
| ID | Identifier |
| IGMP | Internet Group Management Protocol |
| IP | Internet Protocol |
| IPv4 | Internet Protocol version 4 |
| IPv6 | Internet Protocol version 6 (outside this guide's configuration coverage) |
| LACP | Link Aggregation Control Protocol |
| MAC | Media Access Control |
| MDB | Multicast Database |
| MFC | Multicast Forwarding Cache |
| MLD | Multicast Listener Discovery (outside this guide's configuration coverage) |
| NIC | Network Interface Card |
| OS | Operating System |
| PIM | Protocol Independent Multicast |
| PIM-SM | Protocol Independent Multicast — Sparse Mode |
| PVE | Proxmox Virtual Environment |
| RHEL | Red Hat Enterprise Linux |
| RP | Rendezvous Point |
| RPF | Reverse Path Forwarding |
| SM | Sparse Mode |
| SSM | Source-Specific Multicast |
| STP | Spanning Tree Protocol |
| TTL | Time to Live |
| TX | Transmit |
| UDP | User Datagram Protocol |
| UID | User Identifier |
| VE | Virtual Environment |
| VIF | Virtual Interface (multicast forwarding context) |
| VLAN | Virtual Local Area Network |
| VM | Virtual Machine |
| VRF | Virtual Routing and Forwarding |
| ALLMULTI | All-multicast receive flag (interface setting) |
| BPF | Berkeley Packet Filter |
| DVMRP | Distance Vector Multicast Routing Protocol |
| MII | Media Independent Interface |
| PVID | Port VLAN Identifier |
| QEMU | Quick Emulator (virtualization software) |
| TOC | Table of Contents |

## Appendix B — Verification sources

Accessed/reviewed 2026-10-17. These primary sources support the corrected
mechanisms, not a claim that every command or platform was tested. Configuration
choices and example topology are project guidance. No hardware/VM lab validation
was performed during this revision. Pin tool versions and verify installed help,
service units, policy and vendor release notes before deployment.

| ID | Primary source | Verification scope |
|---|---|---|
| L1 | [Linux bridge documentation](https://www.kernel.org/doc/html/latest/networking/bridge.html) | Bridge MDB, snooping, querier and flooding controls |
| L2 | [Linux kernel IP sysctl documentation](https://www.kernel.org/doc/html/latest/networking/ip-sysctl.html) | Effective rp_filter calculation and membership limits; inspect actual host values |
| L3 | [Linux IPv4 socket documentation](https://man7.org/linux/man-pages/man7/ip.7.html) | IPv4 membership/socket behavior |
| L3a | [Debian IPv4 socket manual](https://manpages.debian.org/trixie/manpages/ip.7.en.html) | IP_MULTICAST_ALL and family-specific isolation |
| L4 | [Linux socket manual](https://man7.org/linux/man-pages/man7/socket.7.html) | Receive buffers, effective sizes and overflow observations |
| L5 | [Upstream mcjoin](https://github.com/troglobit/mcjoin) | Test-tool interface and version-specific options |
| L6 | [Upstream smcroute configuration manual](https://github.com/troglobit/smcroute/blob/master/man/smcroute.conf.5) | Membership and routing are distinct operations |
| L7 | [Upstream iperf2 manual](https://iperf2.sourceforge.io/iperf-manpage.html) | Multicast testing; not interchangeable with iperf3 |
| L8 | [systemd service manual](https://man7.org/linux/man-pages/man5/systemd.service.5.html) | Service lifecycle integration; installed unit/build options still need checking |
| L9 | [tcpdump manual](https://man7.org/linux/man-pages/man8/tcpdump.8.html) | Capture options and observation limitations |
| L10 | [nftables manual](https://www.netfilter.org/projects/nftables/manpage.html) | Address families (`bridge`, `netdev`, `ip`, `inet`) and their hooks |
| L11 | [nftables wiki: Bridge filtering](https://wiki.nftables.org/wiki-nftables/index.php/Bridge_filtering) | Native bridge-family filtering without `br_netfilter` |
| G1 | [RFC 2365 — Administratively Scoped IP Multicast](https://www.rfc-editor.org/rfc/rfc2365.html) | 239/8 scope requires configured administrative boundaries; it is not inherent authentication or isolation |

### Qualification still required

| Evidence | Status |
|---|---|
| Exact OS/device/software versions and effective policy | Record and test at the site |
| Commands/scripts and complete data path | Not executed during this review |
| Throughput, loss, failover and recovery | Not measured; examples are not guarantees |
| IPv6/MLD | Explicitly outside this guide |
| Proxmox/ifupdown2 option spelling and live reconfiguration | Verify installed version; attempted online admin-guide retrieval was unavailable |
