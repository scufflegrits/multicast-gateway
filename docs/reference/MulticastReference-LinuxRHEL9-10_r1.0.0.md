# Multicast Reference Guide — Linux (RHEL 9 / RHEL 10), Bare Metal and VMware vSphere 9

**Coverage: IPv4 multicast only.** IPv6/MLD configuration and validation are
outside this guide. mcgw itself retains its separate IPv4/IPv6 design scope.

| Field          | Detail                                    |
|----------------|-------------------------------------------|
| Version        | 1.0.0                                     |
| Last Updated   | 20261017                                  |
| Author         | sysadmin                                  |
| Filename       | MulticastReference-LinuxRHEL9-10_r1.0.0.md |

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

| Version | Date     | Author   | Change Summary                                                                 |
|---------|----------|----------|--------------------------------------------------------------------------------|
| Review 2 | 20261017 | scufflegrits | Second review corrections (F22); see architecture review §7 |
| Review | 20261017 | scufflegrits | IPv4-only scope; technical corrections, clickable navigation, acronym and verification-source appendices; filename/version retained |
| 1.0.0   | 20261016 | sysadmin | Initial release. Covers RHEL 9 and RHEL 10 on bare metal and as VMware vSphere 9 guests |

---

> **Platform Note**
> This guide covers Red Hat Enterprise Linux 9.x and 10.x in two deployment
> forms: installed directly on physical servers (bare metal), and running as
> guest VMs on VMware vSphere 9 (ESXi 9 hosts, vCenter 9). It is the RHEL
> companion to [Debian/Proxmox guide](MulticastReference-LinuxDebian_r1.0.3.md), which covers Debian
> guests on Proxmox. Network topology, VLAN numbering, and switch behavior are
> the same as in the [Cisco guide](MulticastReference-Cisco_r1.0.0.md).
>
> Where RHEL 9 and RHEL 10 differ, the difference is called out. The main
> differences that affect this guide are:
>
> - Network configuration is managed by NetworkManager on both releases. Use
>   `nmcli` (or keyfiles in `/etc/NetworkManager/system-connections/`). Do not
>   write legacy `ifcfg-*` files: they are deprecated on RHEL 9 and not
>   supported on RHEL 10.
> - EPEL is enabled with a release-specific package (`epel-release-latest-9`
>   or `epel-release-latest-10`) and its matching CodeReady Builder repository.
> - Package versions differ. Verify any package with `dnf info <package>`
>   before deploying.
>
> Inspect effective firewalld/SELinux settings rather than assume a default.
> Check tool availability in the approved repositories for the exact release
> and architecture. Source builds are a fallback, not an unconditional requirement.

---

## Table of Contents

- [Scope and command use](#scope-and-command-use)
- [Revision History](#revision-history)
- [1. Overview](#1-overview)
- [2. VMware vSphere 9 Host Configuration](#2-vmware-vsphere-9-host-configuration)
  - [2.1 vSphere Switches and Multicast](#21-vsphere-switches-and-multicast)
  - [2.2 Multicast Filtering Mode](#22-multicast-filtering-mode)
  - [2.3 Recommended Switch and Port Group Configuration](#23-recommended-switch-and-port-group-configuration)
  - [2.4 Port Group VLAN Tagging](#24-port-group-vlan-tagging)
  - [2.5 Uplinks, NIC Teaming and Multicast](#25-uplinks-nic-teaming-and-multicast)
  - [2.6 Verifying on the ESXi Host](#26-verifying-on-the-esxi-host)
- [3. RHEL Network Configuration for Multicast](#3-rhel-network-configuration-for-multicast)
  - [3.1 Interface Naming and NetworkManager](#31-interface-naming-and-networkmanager)
  - [3.2 Bare Metal — Bond and VLAN Configuration](#32-bare-metal--bond-and-vlan-configuration)
  - [3.3 VMware Guest — vmxnet3 Interface Configuration](#33-vmware-guest--vmxnet3-interface-configuration)
  - [3.4 Multicast Interface Selection on Multi-Homed Machines](#34-multicast-interface-selection-on-multi-homed-machines)
    - [How Linux Selects the Multicast Interface](#how-linux-selects-the-multicast-interface)
    - [The Problem With Multiple Interfaces](#the-problem-with-multiple-interfaces)
    - [Mechanism 1 — Add a Specific Multicast Route (Recommended)](#mechanism-1--add-a-specific-multicast-route-recommended)
    - [Mechanism 2 — Bind the Application to a Specific Interface](#mechanism-2--bind-the-application-to-a-specific-interface)
    - [Mechanism 3 — Route Metrics and never-default](#mechanism-3--route-metrics-and-never-default)
    - [Verifying Which Interface Multicast Is Using](#verifying-which-interface-multicast-is-using)
    - [Recommendation for This Environment](#recommendation-for-this-environment)
  - [3.5 firewalld and Multicast](#35-firewalld-and-multicast)
  - [3.6 SELinux and Multicast Tools](#36-selinux-and-multicast-tools)
- [4. Required Packages](#4-required-packages)
  - [4.1 Package Overview](#41-package-overview)
  - [4.2 Installation from RHEL and EPEL](#42-installation-from-rhel-and-epel)
  - [4.3 Building smcroute, mcjoin and pimd from Source](#43-building-smcroute-mcjoin-and-pimd-from-source)
- [5. Multicast Receiver Configuration](#5-multicast-receiver-configuration)
  - [5.1 Joining a Multicast Group Manually](#51-joining-a-multicast-group-manually)
  - [5.2 Using mcjoin as a Receiver](#52-using-mcjoin-as-a-receiver)
  - [5.3 Using iperf2 as a Receiver](#53-using-iperf2-as-a-receiver)
  - [5.4 Using socat as a Receiver](#54-using-socat-as-a-receiver)
  - [5.5 Using smcroute as a Static Receiver](#55-using-smcroute-as-a-static-receiver)
  - [5.6 Using pimd as a Receiver](#56-using-pimd-as-a-receiver)
- [6. Multicast Sender Configuration](#6-multicast-sender-configuration)
  - [6.1 Using mcjoin as a Sender](#61-using-mcjoin-as-a-sender)
  - [6.2 Using iperf2 as a Sender](#62-using-iperf2-as-a-sender)
  - [6.3 Using socat as a Sender](#63-using-socat-as-a-sender)
  - [6.4 smcroute Static Forwarding](#64-smcroute-static-forwarding)
- [7. smcroute vs pimd — Which to Use](#7-smcroute-vs-pimd--which-to-use)
  - [7.1 smcroute Overview](#71-smcroute-overview)
  - [7.2 pimd Overview](#72-pimd-overview)
  - [7.3 Recommendation for This Environment](#73-recommendation-for-this-environment)
- [8. systemd Service Configuration](#8-systemd-service-configuration)
  - [8.1 smcroute as a systemd Service](#81-smcroute-as-a-systemd-service)
  - [8.2 pimd as a systemd Service](#82-pimd-as-a-systemd-service)
- [9. Testing and Verification](#9-testing-and-verification)
  - [9.1 Verification Commands — ESXi Host](#91-verification-commands--esxi-host)
  - [9.2 Verification Commands — RHEL Host or Guest](#92-verification-commands--rhel-host-or-guest)
  - [9.3 Worked End-to-End Test Scenario](#93-worked-end-to-end-test-scenario)
- [10. Troubleshooting](#10-troubleshooting)
  - [10.1 Multicast Not Leaving the RHEL System](#101-multicast-not-leaving-the-rhel-system)
  - [10.2 Multicast Not Arriving at the RHEL System](#102-multicast-not-arriving-at-the-rhel-system)
  - [10.3 IGMP Join Not Seen by Switch](#103-igmp-join-not-seen-by-switch)
  - [10.4 Multicast Works Briefly Then Stops](#104-multicast-works-briefly-then-stops)
  - [10.5 VM Receiving Groups It Did Not Join](#105-vm-receiving-groups-it-did-not-join)
  - [10.6 Multicast Interrupted After vMotion or Uplink Failover](#106-multicast-interrupted-after-vmotion-or-uplink-failover)
- [11. Deep Dive — Advanced Multicast Interface Control](#11-deep-dive--advanced-multicast-interface-control)
  - [11.1 Policy Routing with ip rule](#111-policy-routing-with-ip-rule)
  - [11.2 Multicast Routing Tables](#112-multicast-routing-tables)
  - [11.3 rp_filter — Reverse Path Filtering](#113-rp_filter--reverse-path-filtering)
  - [11.4 igmp_max_memberships and Related Limits](#114-igmp_max_memberships-and-related-limits)
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

This document covers multicast configuration for RHEL 9 and RHEL 10 systems in
an environment where intra-VLAN multicast is required between servers, VMs, and
physical clients connected to Cisco Catalyst access layer switches.

Two deployment forms are covered.

**Bare metal** — RHEL installed directly on a physical server, connected to the
aggregation switch through an LACP bond carrying tagged VLANs:

```
RHEL bare-metal server (VLAN 2601 on bond0.2601)
    ↓ bond0 (LACP 802.3ad, eno1 + eno2)
SWITCH01 (port-channel, trunk)
    ↓ trunk
SWITCH02
    ↓ access port Gi1/0/1
Physical client (VLAN 2601)
```

**VMware guest** — RHEL running as a VM on an ESXi 9 host, with a vmxnet3
virtual NIC attached to a port group on VLAN 2601:

```
RHEL VM (ens224, untagged inside the guest)
    ↓ vmxnet3 vNIC
Port group "PG-VLAN2601" (VLAN ID 2601) on a vSphere Distributed Switch
    ↓ ESXi uplinks (vmnic2 + vmnic3, LAG or teaming)
SWITCH01
    ↓ trunk
SWITCH02
    ↓ access port Gi1/0/1
Physical client (VLAN 2601)
```

Multicast is intra-VLAN only. No inter-VLAN multicast routing is required.
Multicast group addresses are in the 239.0.0.0/8 administratively scoped range.
The Cisco switches handle IGMP snooping and querier duties as described in the
[Cisco guide](MulticastReference-Cisco_r1.0.0.md). The querier for VLAN 2601 is
`10.32.204.254` on SWITCH01.

There is no Linux bridge in either form. On bare metal the RHEL kernel talks to
the switch directly. On VMware, the vSphere switch takes the place that the
Proxmox Linux bridge occupies in the Debian guide, and section 2 covers its
multicast behavior.

Interface names used throughout:

| Deployment | Interface      | Role                                         |
|------------|----------------|----------------------------------------------|
| Bare metal | eno1, eno2     | Physical ports, members of bond0             |
| Bare metal | bond0          | LACP bond, no IP address                     |
| Bare metal | bond0.2601     | VLAN 2601 data interface, 192.168.1.10/24     |
| Bare metal | bond0.200      | Management VLAN, default gateway             |
| VMware VM  | ens192         | Management vNIC, default gateway             |
| VMware VM  | ens224         | VLAN 2601 data vNIC, 192.168.1.10/24          |

Substitute the real names from `ip -br link` on your systems.

---

## 2. VMware vSphere 9 Host Configuration

This section applies only to RHEL guests on VMware. Skip it for bare metal.

### 2.1 vSphere Switches and Multicast

A RHEL VM's vNIC connects to a port group on either a vSphere Standard Switch
(vSS, configured per host) or a vSphere Distributed Switch (vDS, configured in
vCenter and shared across hosts). Both switches sit between the guest and the
physical uplinks in the same way the Proxmox Linux bridge does in the Debian
guide, but they handle multicast differently from a Linux bridge:

- **Neither switch acts as an IGMP querier.** Queries come only from the
  physical network (SWITCH01 in this environment).
- **IGMP reports from the guest are passed to the physical uplink**, so the
  upstream Cisco switch learns membership on the ESXi uplink port.
- **The vSS supports only basic multicast filtering.** The vDS supports basic
  filtering and IGMP/MLD snooping (section 2.2).

The flow for a join from a RHEL VM:

```
RHEL VM sends IGMP membership report on ens224
    ↓
vmxnet3 vNIC → port group PG-VLAN2601 (switch learns membership)
    ↓
ESXi uplink chosen by the teaming policy, tagged VLAN 2601
    ↓
SWITCH01 snoops the report on the uplink port
    ↓
SWITCH01 forwards group traffic to the ESXi uplink port
```

### 2.2 Multicast Filtering Mode

The vSphere switch decides which VMs in a port group receive a multicast frame.
There are two modes.

| Mode                 | Available on | Behavior                                                                                   |
|----------------------|--------------|--------------------------------------------------------------------------------------------|
| Basic (inspect effective setting)      | vSS and vDS  | Forwards by destination multicast MAC, using the multicast filter list the guest driver programs into its vNIC. Source addresses are ignored. |
| IGMP/MLD snooping    | vDS only     | Product mode named IGMP/MLD snooping; this guide considers only its IPv4 IGMP/group/source behavior and requires build qualification. |

Consequences of basic mode:

- Because 32 IPv4 groups share each multicast MAC (low 23 bits of the IP map
  into the MAC), a VM that joins 239.1.1.1 also receives frames for 224.1.1.1,
  239.129.1.1 and the other overlapping groups. The guest kernel discards the
  ones it did not join, but they still cost CPU and vNIC bandwidth.
- Source-specific (SSM) filtering is not enforced by the switch.
- Basic mode does not depend on IGMP timers, so the vSphere switch itself never
  ages out a membership. Aging happens only on the physical switch.

Consequences of IGMP/MLD snooping mode:

- Group delivery is exact (no MAC overlap) and IGMPv3 source lists are honored.
- The vDS maintains its own membership table, which must be refreshed by the
  VMs' responses to the physical querier's general queries. If the guest's
  firewall drops queries (section 3.5) the vDS entry and the physical switch
  entry both age out.

For this environment, which uses a small number of 239.x.x.x groups with no
SSM, **basic mode is sufficient**. Use IGMP/MLD snooping mode on the vDS if
VLAN 2601 carries many groups or high-rate streams that not every VM needs.

Set the mode in the vSphere Client:

```
vCenter → Networking → <vDS> → Configure → Settings → Properties → Edit
    → Advanced → Multicast filtering mode → Basic | IGMP/MLD snooping
```

The setting applies to the whole vDS, not per port group.

### 2.3 Recommended Switch and Port Group Configuration

Recommended vDS port group settings for multicast VLANs:

```
Port group name          PG-VLAN2601
VLAN type                VLAN
VLAN ID                  2601
Teaming and failover     Route based on originating virtual port
                         (or the vDS LAG as active uplink — section 2.5)
Notify switches          Yes
Failback                 Yes
Security — Promiscuous   Reject
Security — MAC changes   Reject
Security — Forged tx     Reject
```

Rationale in the context of multicast:

```
VLAN ID 2601             The switch tags guest frames with VLAN 2601 on the
                         uplink. The guest sees an untagged interface.

Promiscuous mode Reject  Not needed for multicast. Multicast delivery uses the
                         vNIC's multicast filter (basic mode) or snooping
                         state. Enabling promiscuous mode makes the VM receive
                         all traffic on the port group and hides filtering
                         problems instead of fixing them.

Forged transmits Reject  Not needed for multicast. A RHEL sender uses its own
                         vNIC MAC as the source MAC.

Notify switches Yes      After a failover the host sends RARP frames so the
                         physical switch relearns the VM's MAC. This does not
                         re-send IGMP membership (section 10.6).
```

On a vSS the same settings exist per port group in the host's networking
configuration. The vSS has no multicast filtering mode setting; it always uses
basic mode.

### 2.4 Port Group VLAN Tagging

| VLAN setting on port group | Guest sees           | Use                                       |
|----------------------------|----------------------|-------------------------------------------|
| VLAN ID 2601 (VST)         | Untagged frames      | Recommended. One vNIC per multicast VLAN. |
| VLAN trunking 4095 / range (VGT) | 802.1Q tagged frames | Guest creates VLAN subinterfaces with nmcli. Use only when a VM needs many VLANs. |
| None (EST)                 | Native VLAN of uplink | Not used in this environment.             |

With VST, multicast in VLAN 2601 is delivered only to vNICs in port groups with
VLAN ID 2601. VLAN isolation is enforced by the vSphere switch regardless of
the multicast filtering mode, under correct port-group/trunk configuration; verify rather than assume isolation.

### 2.5 Uplinks, NIC Teaming and Multicast

An IGMP report from a VM leaves the host through exactly one uplink. Which one
depends on the teaming policy:

| Teaming policy                               | Uplink for a VM's multicast and IGMP | Physical switch config |
|----------------------------------------------|--------------------------------------|------------------------|
| Route based on originating virtual port      | Fixed per vNIC port                  | Independent trunk ports, no port-channel |
| Route based on source MAC hash               | Fixed per vNIC MAC                   | Independent trunk ports |
| Route based on IP hash                       | Hash of source and destination IP    | Static EtherChannel (`mode on`) |
| vDS LAG (LACP)                               | LAG hash algorithm                   | LACP port-channel (`mode active`) |

With independent trunk ports (the first two policies), the physical switch sees
the VM's membership only on the uplink that the VM is pinned to. Group traffic
is sent to that port only. This is correct as long as the VM stays on that
uplink.

With a port-channel (IP hash or LAG), the switch treats both uplinks as one
logical port, so membership is associated with the logical port-channel; validate actual
failover/convergence instead of assuming uninterrupted delivery. This matches the LACP bond design used for the Proxmox hosts.

**Do not mix:** IP hash on the ESXi side requires a static EtherChannel on the
switch, and a LAG requires LACP. A mismatch causes MAC flapping and
intermittent multicast loss.

### 2.6 Verifying on the ESXi Host

Enable SSH on the ESXi host (or use the ESXi Shell) for these commands.

List distributed switches and their uplinks:

```
esxcli network vswitch dvs vmware list
```

List standard switch port groups and their VLANs:

```
esxcli network vswitch standard portgroup list
```

Find the switch port ID of a VM's vNIC:

```
net-stats -l
```

The output lists `PortNum`, `Type`, `SwitchName`, `MACAddress` and `ClientName`.
The `ClientName` column shows the VM name and vNIC (for example `rhel-mc01.eth1`).

Capture traffic at the VM's switch port in both directions and decode it with
`tcpdump-uw`:

```
pktcap-uw --switchport <PortNum> --dir 2 -o - | tcpdump-uw -enr -
```

Capture on a physical uplink:

```
pktcap-uw --uplink vmnic2 --dir 2 -o - | tcpdump-uw -enr - 'vlan 2601'
```

Write a capture to a file to copy off the host and open in Wireshark:

```
pktcap-uw --uplink vmnic2 --dir 2 -o /tmp/vmnic2.pcap
```

`--dir 0` captures frames entering the switch from that port, `--dir 1`
captures frames leaving it, and `--dir 2` captures both.

Check uplink status:

```
esxcli network nic list
```

All uplinks used by the port group must show `Link Status: Up`.

---

## 3. RHEL Network Configuration for Multicast

### 3.1 Interface Naming and NetworkManager

RHEL uses predictable interface names. Physical servers usually have `eno1`,
`eno2` (onboard) or `ens1f0`, `ens1f1` (PCIe). VMware guests with vmxnet3
vNICs usually have `ens192`, `ens224`, `ens256` and so on.

NetworkManager owns interface configuration on RHEL 9 and RHEL 10. All
persistent settings in this guide are made with `nmcli` and take effect with
`nmcli connection up <name>`. Changes made with `ip` are runtime-only and
NetworkManager may remove them the next time it reapplies the connection.

List connections and devices:

```
nmcli connection show
nmcli device status
```

Show the full settings of one connection:

```
nmcli connection show ens224
```

Connection profiles are stored as keyfiles in
`/etc/NetworkManager/system-connections/`. Do not create `ifcfg-*` files in
`/etc/sysconfig/network-scripts/`.

### 3.2 Bare Metal — Bond and VLAN Configuration

The bare-metal server uses an LACP bond to SWITCH01 carrying the management
VLAN and VLAN 2601, mirroring the Proxmox bond in the Debian guide.

Create the bond with no IP address of its own:

```
sudo nmcli connection add type bond con-name bond0 ifname bond0 \
    bond.options "mode=802.3ad,miimon=100,lacp_rate=fast,xmit_hash_policy=layer2+3,updelay=200,downdelay=200" \
    ipv4.method disabled ipv6.method disabled
```

Add the physical ports to the bond:

```
sudo nmcli connection add type ethernet con-name bond0-eno1 ifname eno1 master bond0
sudo nmcli connection add type ethernet con-name bond0-eno2 ifname eno2 master bond0
```

Create the management VLAN with the default gateway:

```
sudo nmcli connection add type vlan con-name bond0.200 ifname bond0.200 \
    dev bond0 id 200 \
    ipv4.method manual ipv4.addresses 10.32.200.10/24 ipv4.gateway 10.32.200.254
```

Create the multicast VLAN with no gateway and an explicit multicast route:

```
sudo nmcli connection add type vlan con-name bond0.2601 ifname bond0.2601 \
    dev bond0 id 2601 \
    ipv4.method manual ipv4.addresses 192.168.1.10/24 \
    ipv4.never-default yes \
    ipv4.routes "239.0.0.0/8"
```

Bring everything up:

```
sudo nmcli connection up bond0
sudo nmcli connection up bond0.200
sudo nmcli connection up bond0.2601
```

Verify the bond and its LACP state:

```
cat /proc/net/bonding/bond0
```

Both ports must show `MII Status: up` and the same `Aggregator ID`. A port with
a different aggregator ID is not in the LACP bundle; check the port-channel on
SWITCH01.

Rationale for each setting in the context of multicast:

```
mode=802.3ad              LACP. SWITCH01 sees one logical port, so IGMP
                          membership is not tied to a single physical link.

xmit_hash_policy=layer2+3 Transmit hashing uses MAC and IP. Different groups
                          may leave through different ports; the switch
                          handles this because both ports are in one
                          port-channel. No special bond setting is needed
                          for multicast.

ipv4.never-default yes    The data VLAN never installs a default route, so
                          it cannot win default-route selection for multicast
                          (section 3.4).

ipv4.routes 239.0.0.0/8   Sends all 239.x.x.x traffic and IGMP joins out
                          bond0.2601 unless an application chooses another
                          interface.
```

### 3.3 VMware Guest — vmxnet3 Interface Configuration

Confirm the vNIC uses the vmxnet3 driver:

```
ethtool -i ens224
```

Expected output includes `driver: vmxnet3`. An `e1000e` vNIC also passes
multicast but uses more CPU per packet; change the adapter type in the VM
settings if possible.

Install VMware Tools (open-vm-tools is in the RHEL BaseOS/AppStream
repositories) so vCenter reports the guest's IP addresses correctly:

```
sudo dnf install -y open-vm-tools
sudo systemctl enable --now vmtoolsd
```

Configure the multicast vNIC. The connection name usually matches the device
name; check with `nmcli connection show`:

```
sudo nmcli connection modify ens224 \
    ipv4.method manual ipv4.addresses 192.168.1.10/24 \
    ipv4.never-default yes \
    ipv4.routes "239.0.0.0/8"
sudo nmcli connection up ens224
```

The management vNIC (ens192) keeps the default gateway. The guest does not
configure 802.1Q tagging on ens224; the port group adds the VLAN 2601 tag.

### 3.4 Multicast Interface Selection on Multi-Homed Machines

A multi-homed machine has more than one active network interface. Both
deployment forms in this guide are multi-homed (management plus VLAN 2601), so
multicast interface selection must be controlled explicitly.

#### How Linux Selects the Multicast Interface

When an application sends to a multicast group or joins one without naming an
interface, the kernel looks up the group address in the routing table. For
239.x.x.x destinations it uses a route that covers the group (for example
239.0.0.0/8), or falls back to the default route.

Check which interface the kernel would use:

```
ip route get 239.1.1.1
```

The `dev` field in the output is the selected interface.

List any routes that cover multicast:

```
ip route show table all | grep -E '^(multicast )?2(2[4-9]|3[0-9])\.'
```

#### The Problem With Multiple Interfaces

Consider a VMware guest with:

```
ens192 — management, IP 10.32.200.x,  gateway 10.32.200.254
ens224 — VLAN 2601,  IP 192.168.1.10, no gateway
```

Without a 239.0.0.0/8 route, `ip route get 239.1.1.1` returns ens192 because
it holds the only default route. Both the application's multicast data and the
kernel's IGMP join leave through ens192:

```
Application joins 239.1.1.1 without naming an interface
    ↓
Kernel looks up 239.1.1.1 in the routing table
    ↓
Default route via ens192 wins
    ↓
IGMP join exits ens192 (management VLAN) instead of ens224
    ↓
SWITCH01 sees no join on VLAN 2601
    ↓
Multicast is never delivered to the RHEL system
```

#### Mechanism 1 — Add a Specific Multicast Route (Recommended)

Add a route for 239.0.0.0/8 through the multicast interface. This is a
system-wide setting that applies to every application that does not choose an
interface itself.

Persistently, through NetworkManager:

```
sudo nmcli connection modify ens224 +ipv4.routes "239.0.0.0/8"
sudo nmcli connection up ens224
```

Temporarily, for testing (removed when NetworkManager reapplies the connection
or at reboot):

```
sudo ip route add 239.0.0.0/8 dev ens224
```

Verify:

```
ip route show | grep 239
ip route get 239.1.1.1
```

Remove the persistent route:

```
sudo nmcli connection modify ens224 -ipv4.routes "239.0.0.0/8"
sudo nmcli connection up ens224
```

#### Mechanism 2 — Bind the Application to a Specific Interface

Explicit membership-interface selection controls the join. Outgoing multicast
interface selection and local source binding are separate controls; inspect the
chosen tool's socket behavior and confirm by capture.

mcjoin, with `-i`:

```
# Receiver — join on ens224
mcjoin -i ens224 -p 5001 239.1.1.1

# Sender — send from ens224
mcjoin -i ens224 -s -p 5001 239.1.1.1
```

iperf2, with `%<device>` on the bind address (receiver) or the source address
(sender):

```
# Receiver
iperf -s -u -B 239.1.1.1%ens224 -p 5001 -i 1

# Sender
iperf -c 239.1.1.1 -u -B 192.168.1.10 -p 5001 -T 1 -t 30
```

Kernel-level join on a named interface, without any application:

```
sudo ip addr add 239.1.1.1/32 dev ens224 autojoin
```

#### Mechanism 3 — Route Metrics and never-default

Adjusting default-route metrics affects all traffic on the machine. In this
environment the correct approach is the opposite: make sure the data interface
never installs a default route at all.

```
sudo nmcli connection modify ens224 ipv4.never-default yes
sudo nmcli connection up ens224
```

If a data interface must have a gateway (for example, DHCP that always supplies
one), give it a higher metric than the management interface so it never wins:

```
sudo nmcli connection modify ens224 ipv4.route-metric 500
sudo nmcli connection up ens224
```

Use Mechanism 1 in preference to metric changes when only multicast selection
needs to be corrected.

#### Verifying Which Interface Multicast Is Using

Check the routing decision:

```
ip route get 239.1.1.1
```

Capture IGMP on each interface in separate terminals:

```
# Terminal 1 — intended multicast interface
sudo tcpdump -i ens224 -nn igmp

# Terminal 2 — competing interface
sudo tcpdump -i ens192 -nn igmp
```

Start the application and see which terminal shows the membership report.

Verify kernel-level membership:

```
ip maddr show dev ens224
cat /proc/net/igmp
```

#### Recommendation for This Environment

```
1. Set ipv4.never-default yes on every data/multicast interface.

2. If default interface selection needs it, add a deliberately scoped route
   after checking other feeds; explicit membership selection is preferable.

3. Always name the interface in test tools (mcjoin -i, iperf -B ...%dev,
   smcroute mgroup from <if>). Belt-and-suspenders with Mechanism 1.

4. Put the multicast interface in a firewalld zone that accepts IGMP and the
   application's UDP ports (section 3.5).

5. Check rp_filter on the multicast interface (section 11.3).

6. Use ip route get 239.1.1.1 as the first diagnostic step whenever
   multicast is not reaching its destination on a multi-homed machine.
```

### 3.5 firewalld and Multicast

Inspect whether firewalld is active, which zone owns the ingress interface,
and whether the current policy admits data and queries:

1. **IGMP queries can be blocked by policy.** The kernel must receive the querier's general
   queries to answer them. If the firewall drops IGMP, the RHEL system joins
   successfully, receives traffic for a few minutes, and then the switch ages
   out its membership (timing depends on the effective membership/query settings). See section
   10.4.
2. **Multicast UDP data requires an effective allow path**; inspect whether the destination port/group is allowed in
   the zone of the receiving interface. Do not rely on connection tracking alone to admit a new
   unsolicited feed; inspect actual rule counters.

Check the zone of each interface:

```
firewall-cmd --get-active-zones
```

The recommended approach is to place the multicast interface in its own zone
and allow only what it needs. Assign the zone through NetworkManager so it
persists with the connection:

```
sudo nmcli connection modify ens224 connection.zone internal
sudo nmcli connection up ens224
```

Allow IGMP and the multicast application's UDP ports in that zone:

```
sudo firewall-cmd --permanent --zone=internal --add-protocol=igmp
sudo firewall-cmd --permanent --zone=internal --add-port=5001/udp
sudo firewall-cmd --reload
```

To accept the UDP port only for multicast destinations, use a rich rule instead
of `--add-port`:

```
sudo firewall-cmd --permanent --zone=internal --add-rich-rule='rule family="ipv4" destination address="239.0.0.0/8" port port="5001" protocol="udp" accept'
sudo firewall-cmd --reload
```

Verify:

```
sudo firewall-cmd --zone=internal --list-all
```


**Do not add iptables rules alongside firewalld.** firewalld uses nftables on
RHEL 9 and RHEL 10. Rules added with `iptables` or `nft` directly are not part
of firewalld's configuration, have lifecycle/ordering independent of firewalld and make the
effective policy hard to read. If firewalld is disabled by policy and nftables
is managed directly, add the equivalent rules to the managed ruleset.

Inspect the effective nftables ruleset generated by firewalld:

```
sudo nft list ruleset | less
```

### 3.6 SELinux and Multicast Tools

Inspect enforcing state, process domain, file labels and AVC denials on the
actual host. Service confinement depends on policy and labels, not simply the
binary installation directory. Do not assume administrator tools are always
unconfined or that every custom service enters `unconfined_service_t`.

After installing specific files, restore expected labels according to the
host policy; do not broadly relabel unrelated system trees.

```
sudo restorecon -v /usr/sbin/smcrouted /usr/sbin/smcroutectl /etc/smcroute.conf
```

Check the domain a service is running in:

```
ps -eZ | grep -E 'smcrouted|pimd'
```

Check for recent denials:

```
sudo ausearch -m AVC -ts recent
```

Do not disable SELinux or set it to permissive to "fix" multicast. Check interface selection, firewalld, rp_filter, switch/querier state and actual
AVC evidence independently; do not rule out a layer solely from an assumed frequency.

---

## 4. Required Packages

### 4.1 Package Overview

| Package          | Source            | Purpose                                                      |
|------------------|-------------------|--------------------------------------------------------------|
| iproute          | RHEL BaseOS       | `ip` command for interfaces, routes and multicast membership |
| iputils          | RHEL BaseOS       | `ping`                                                       |
| tcpdump          | RHEL AppStream    | Packet capture for multicast verification                    |
| socat            | RHEL AppStream    | Simple multicast receiver and sender with no extra repos     |
| wireshark-cli    | RHEL AppStream    | `tshark` for headless capture with protocol decoding         |
| ethtool          | RHEL BaseOS       | NIC driver and counter inspection                            |
| iperf            | EPEL              | iperf 2 — throughput testing with multicast UDP support      |
| smcroute         | Check repo / source fallback   | Static multicast group join and routing daemon               |
| mcjoin           | Check repo / source fallback   | Minimal multicast join and send tool for testing             |
| pimd             | Check repo / source fallback   | PIM-SM/SSM multicast routing daemon (routed environments only) |
| open-vm-tools    | RHEL AppStream    | VMware guest tools (VMware guests only)                      |

Notes:

- **iperf3 does not support multicast.** The `iperf3` package in RHEL is useful
  for unicast throughput testing only. Use `iperf` (iperf 2) from EPEL for
  multicast tests.
- Check `dnf info smcroute mcjoin pimd` against approved repositories for the
  exact release/architecture. Fedora or COPR availability is not proof of official
  RHEL/EPEL availability. If absent, an approved pinned source build (section 4.3)
  is a fallback, with its own update responsibility.
- socat is the fallback test tool when EPEL and source builds are not allowed.

### 4.2 Installation from RHEL and EPEL

Install the tools from the RHEL repositories:

```
sudo dnf install -y iproute iputils tcpdump socat wireshark-cli ethtool
```

Enable EPEL. EPEL depends on packages in CodeReady Builder, so enable that
first.

RHEL 9:

```
sudo subscription-manager repos --enable codeready-builder-for-rhel-9-$(arch)-rpms
sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
```

RHEL 10:

```
sudo subscription-manager repos --enable codeready-builder-for-rhel-10-$(arch)-rpms
sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm
```

If the system gets content from Satellite or another internal mirror, enable
the mirrored CodeReady Builder and EPEL repositories there instead.

Install iperf 2:

```
sudo dnf install -y iperf
```

Verify installed versions:

```
iperf --version
tcpdump --version
tshark --version
socat -V | head -2
```

To allow a non-root user to capture with tshark, add the user to the
`wireshark` group and log in again:

```
sudo usermod -aG wireshark $USER
```

### 4.3 Building smcroute, mcjoin and pimd from Source

Build on a staging system or in a build VM, not on production hosts, where
possible. The steps below are the upstream build steps for a release tarball.
Download releases from the GitHub releases pages of `troglobit/smcroute`,
`troglobit/mcjoin` and `troglobit/pimd`, and verify the checksum published with
each release.

Install the build dependencies:

```
sudo dnf install -y gcc make pkgconf-pkg-config libcap-devel systemd-devel tar gzip
```

Building from a git checkout instead of a release tarball also needs
`autoconf` and `automake`, and an `./autogen.sh` step before `./configure`.

**smcroute:**

```
tar xf smcroute-<version>.tar.gz
cd smcroute-<version>
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var
make -j"$(nproc)"
sudo make install-strip
```

Unit installation depends on configure/build options; inspect the build output.
Check with `systemctl cat smcroute`. If no unit was installed, use the unit in
section 8.1.

**mcjoin:**

```
tar xf mcjoin-<version>.tar.gz
cd mcjoin-<version>
./configure --prefix=/usr
make -j"$(nproc)"
sudo make install-strip
```

**pimd** (only if routed multicast is required — see section 7):

```
tar xf pimd-<version>.tar.gz
cd pimd-<version>
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var
make -j"$(nproc)"
sudo make install-strip
```

After installing, restore SELinux labels (section 3.6):

```
sudo restorecon -v /usr/sbin/smcrouted /usr/sbin/smcroutectl /usr/bin/mcjoin /usr/sbin/pimd
```

Verify:

```
smcrouted -v
mcjoin -v
pimd -v
```

In mcjoin, `-v` prints the version. It is not a verbose flag.

Source-built tools are not updated by `dnf update`. Record the version and
source of each one in the system's build notes and rebuild when upstream
publishes a fix.

---

## 5. Multicast Receiver Configuration

### 5.1 Joining a Multicast Group Manually

The `ip` command can join a group at the kernel level with no daemon. This tests
whether the network delivers multicast before any application is involved.

```
sudo ip addr add 239.1.1.1/32 dev ens224 autojoin
```

The `autojoin` flag makes the kernel send an IGMP membership report for the
group immediately and answer later queries for it.

Verify:

```
ip maddr show dev ens224
```

Expected output includes:

```
3:  ens224
    link  01:00:5e:01:01:01
    inet  239.1.1.1
```

Leave the group:

```
sudo ip addr del 239.1.1.1/32 dev ens224
```

This join is runtime-only. It does not make traffic reach an application; it
only causes the network to deliver the group to the interface, which is enough
to confirm delivery with tcpdump.

### 5.2 Using mcjoin as a Receiver

mcjoin is a small tool designed for multicast testing. It joins groups and
counts received packets.

Join a group on the default port (1234):

```
mcjoin -i ens224 239.1.1.1
```

Join on a specific UDP port:

```
mcjoin -i ens224 -p 5001 239.1.1.1
```

Join several groups:

```
mcjoin -i ens224 -p 5001 239.1.1.1 239.1.1.2 239.1.1.3
```

Join a range of groups with `+NUM` (here 239.1.1.1 to 239.1.1.10):

```
mcjoin -i ens224 -p 5001 239.1.1.1+10
```

Source-specific join (IGMPv3), as `SOURCE,GROUP`:

```
mcjoin -i ens224 -p 5001 192.168.1.20,239.1.1.1
```

Plain output without the progress display (useful in logs):

```
mcjoin -i ens224 -p 5001 -o 239.1.1.1
```

Debug logging:

```
mcjoin -i ens224 -p 5001 -l debug 239.1.1.1
```

Stop after a number of packets or seconds:

```
mcjoin -i ens224 -p 5001 -c 100 239.1.1.1
mcjoin -i ens224 -p 5001 -W 60 239.1.1.1
```

### 5.3 Using iperf2 as a Receiver

iperf 2 (package `iperf` from EPEL) supports multicast in server mode. Binding
the server to a group address makes it join the group.

```
iperf -s -u -B 239.1.1.1%ens224 -p 5001 -i 1
```

Parameters:

```
-s                    Server mode (receiver)
-u                    UDP
-B 239.1.1.1%ens224   Bind to the group and join it on ens224
-p 5001               UDP port
-i 1                  Report every second
```

Source-specific join:

```
iperf -s -u -B 239.1.1.1%ens224 -H 192.168.1.20 -p 5001 -i 1
```

`-H` (`--ssm-host`) sets the source address for an IGMPv3 source-specific join.

The iperf server reports loss and jitter per interval, which makes it a better
choice than mcjoin when measuring stream quality.

### 5.4 Using socat as a Receiver

socat is in the RHEL AppStream repository and needs no EPEL or source build.

Receive group 239.1.1.1 on port 5001 through ens224 and print payloads:

```
socat -u UDP4-RECV:5001,ip-add-membership=239.1.1.1:ens224 STDOUT
```

socat prints payloads only. For packet counts and loss figures, use mcjoin or
iperf2.

### 5.5 Using smcroute as a Static Receiver

smcroute can join groups at daemon startup and hold them for as long as the
daemon runs. This is useful when an application expects the group to be present
on the interface but does not join it itself.

Edit the configuration file:

```
sudo vi /etc/smcroute.conf
```

Example configuration:

```
# Join multicast group 239.1.1.1 on ens224
mgroup from ens224 group 239.1.1.1

# Join more groups
mgroup from ens224 group 239.1.1.2
mgroup from ens224 group 239.1.1.3

# Source-specific join (IGMPv3)
# mgroup from ens224 group 239.1.1.4 source 192.168.1.20
```

The `mgroup` directive opens a socket and joins the group on the named
interface. The kernel sends the IGMP report and answers later queries for as
long as the socket stays open. No forwarding is performed by `mgroup`.

Test in the foreground:

```
sudo smcrouted -n -f /etc/smcroute.conf
```

`-n` keeps the daemon in the foreground. Stop it with Ctrl+C.

Verify the join:

```
sudo tcpdump -i ens224 -nn igmp
```

You should see an IGMP membership report for 239.1.1.1 from 192.168.1.10.

### 5.6 Using pimd as a Receiver

pimd is a PIM-SM and PIM-SSM routing daemon. It does not join groups on behalf
of local applications; it builds multicast routes between interfaces. In an
intra-VLAN environment pimd has no role as a receiver. Use mcjoin, iperf2,
socat, smcroute, or the application's own join.

See section 7 for when pimd is appropriate.

---

## 6. Multicast Sender Configuration

### 6.1 Using mcjoin as a Sender

Send to a group on ens224 (default port 1234, one packet every 100 ms):

```
mcjoin -i ens224 -s 239.1.1.1
```

Send on a specific port at one packet per second (`-f` is the interval in
milliseconds):

```
mcjoin -i ens224 -s -p 5001 -f 1000 239.1.1.1
```

Set the TTL explicitly. The default is 1, which keeps traffic on the local
subnet and is correct for intra-VLAN use:

```
mcjoin -i ens224 -s -p 5001 -t 1 239.1.1.1
```

Send to several groups:

```
mcjoin -i ens224 -s -p 5001 239.1.1.1 239.1.1.2
```

Set the payload size in bytes:

```
mcjoin -i ens224 -s -p 5001 -b 1200 239.1.1.1
```

A sender does not need to join a group to send to it.

### 6.2 Using iperf2 as a Sender

Send multicast UDP at 1 Mbit/s for 30 seconds:

```
iperf -c 239.1.1.1 -u -b 1M -p 5001 -T 1 -t 30
```

Parameters:

```
-c 239.1.1.1   Send to the multicast group
-u             UDP (required for multicast)
-b 1M          Target rate 1 Mbit/s
-p 5001        Destination port, matching the receiver
-T 1           Multicast TTL (1 = local subnet only)
-t 30          Run for 30 seconds
```

Send from a specific source address so the traffic leaves ens224:

```
iperf -c 239.1.1.1 -u -b 1M -p 5001 -T 1 -t 30 -B 192.168.1.10
```

Set the datagram size (bytes):

```
iperf -c 239.1.1.1 -u -b 10M -l 1316 -p 5001 -T 1 -t 30 -B 192.168.1.10
```

### 6.3 Using socat as a Sender

Send each line typed on standard input as one datagram:

```
socat -u STDIN UDP4-DATAGRAM:239.1.1.1:5001,ip-multicast-if=192.168.1.10,ip-multicast-ttl=1
```

Send a timestamp once per second:

```
while sleep 1; do date; done | \
    socat -u STDIN UDP4-DATAGRAM:239.1.1.1:5001,ip-multicast-if=192.168.1.10,ip-multicast-ttl=1
```

`ip-multicast-if` takes the local IP address of the outgoing interface.

### 6.4 smcroute Static Forwarding

smcroute can install static multicast routes that forward a group from one
interface to another. It does not originate traffic, so it is not a sender.

A static route has an inbound interface, an optional source, a group, and one or
more outbound interfaces:

```
sudo smcroutectl add bond0.2601 192.168.1.20 239.1.1.1 bond0.2602
```

This forwards traffic from 192.168.1.20 to 239.1.1.1 arriving on bond0.2601 out
of bond0.2602. The same route in `/etc/smcroute.conf`:

```
mroute from bond0.2601 source 192.168.1.20 group 239.1.1.1 to bond0.2602
```

The outbound interface must differ from the inbound one: the kernel never
forwards a multicast packet back out of the interface it arrived on. The
sender's TTL must also be greater than 1, because forwarding decrements the TTL
and a packet with TTL 1 is not forwarded.

Static forwarding is inter-VLAN multicast routing, which this environment does
not use. It is documented here for completeness.

---

## 7. smcroute vs pimd — Which to Use

### 7.1 smcroute Overview

smcroute is a static multicast routing daemon. It does not run a multicast
routing protocol. It manages group joins (`mgroup`) and static forwarding
routes (`mroute`) from a configuration file or at runtime with `smcroutectl`.

Strengths:

```
- Simple configuration with no protocol traffic
- Joins groups on a named interface, including source-specific (SSM) joins
- Holds joins for as long as the daemon runs
- Low resource use
- No Rendezvous Point or PIM neighbors needed
```

Limitations:

```
- No dynamic routing — every forwarding route is configured by hand
- Cannot discover sources or receivers automatically
- Not a replacement for PIM where multicast must cross routed boundaries
  dynamically
- Not packaged for RHEL; built from source (section 4.3)
```

### 7.2 pimd Overview

pimd is a PIM-SM (Protocol Independent Multicast — Sparse Mode) daemon with
PIM-SSM support. It discovers PIM neighbors, uses a Rendezvous Point for
any-source groups, and builds distribution trees dynamically.

Strengths:

```
- Dynamic multicast routing across routed boundaries
- PIM-SSM for source-specific groups (232.0.0.0/8) without an RP
- Interoperates with Cisco PIM-SM
```

Limitations:

```
- Any-source groups (such as 239.x.x.x) need an RP; without one they are not
  routed
- No dense-mode fallback. Dense mode is a separate daemon (pimd-dense)
- Acts as IGMP querier on every enabled interface and can win the querier
  election against the Cisco querier (section 11.7)
- More complex to configure and troubleshoot
- Not packaged for RHEL; built from source (section 4.3)
```

### 7.3 Recommendation for This Environment

For intra-VLAN multicast with no inter-VLAN routing and groups in 239.0.0.0/8:

```
Use the application's own joins. Use smcroute only where an application
needs the OS to hold the join. Do not run pimd.
```

Rationale:

- All multicast stays within one VLAN, so no multicast routing is needed.
- Most multicast applications join their own groups. Neither daemon is needed
  for them.
- smcroute provides a persistent join with minimal configuration and sends no
  protocol traffic that could confuse the Cisco switches.
- pimd would act as an IGMP querier and send PIM hellos on VLAN 2601. With a
  lower IP address than 10.32.204.254 it would take over the querier role
  from SWITCH01.
- Introduce pimd only if inter-VLAN multicast routing is added later, with an
  RP configured on the Cisco side for any-source groups.

---

## 8. systemd Service Configuration

### 8.1 smcroute as a systemd Service

Check whether the source build installed a unit:

```
systemctl cat smcroute
```

If it did not, create `/etc/systemd/system/smcroute.service`:

```
[Unit]
Description=Static multicast routing daemon
Documentation=man:smcrouted(8) man:smcroute.conf(5)
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/sbin/smcrouted -n -s -f /etc/smcroute.conf
ExecReload=/usr/sbin/smcroutectl reload
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

`After=network-online.target` matters: `mgroup` joins fail if the interface is
not up when the daemon starts. Make sure NetworkManager's wait-online service
is enabled so this target is meaningful:

```
systemctl is-enabled NetworkManager-wait-online.service
```

If the unit was installed by the build, add restart-on-failure as an override
instead of editing the unit:

```
sudo systemctl edit smcroute
```

Add:

```
[Service]
Restart=on-failure
RestartSec=5s
```

`systemctl edit` reloads systemd automatically when the editor closes.

Label the files, then enable and start the service:

```
sudo restorecon -v /etc/systemd/system/smcroute.service /etc/smcroute.conf
sudo systemctl daemon-reload
sudo systemctl enable --now smcroute
```

Verify:

```
systemctl status smcroute
systemctl show smcroute -p Restart -p RestartUSec
sudo smcroutectl show groups
```

View logs:

```
sudo journalctl -u smcroute -f
```

Full configuration example for a RHEL VM on VLAN 2601 that must hold groups
239.1.1.1 and 239.1.1.2:

```
# /etc/smcroute.conf
# Join multicast groups on ens224 at daemon startup

mgroup from ens224 group 239.1.1.1
mgroup from ens224 group 239.1.1.2
```

Apply configuration changes:

```
sudo systemctl reload smcroute
```

### 8.2 pimd as a systemd Service

Only for routed multicast environments (section 7.3).

Check whether the build installed a unit:

```
systemctl cat pimd
```

If not, create `/etc/systemd/system/pimd.service`:

```
[Unit]
Description=PIM-SM/SSM multicast routing daemon
Documentation=man:pimd(8) man:pimd.conf(5)
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/sbin/pimd -n -s
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

pimd reads `/etc/pimd.conf` by default.

Minimal configuration that enables PIM on one interface only and names an RP for
the any-source range:

```
# /etc/pimd.conf
# Enable PIM only on the routed multicast interfaces
phyint bond0.2601 enable
phyint bond0.2602 enable
phyint bond0.200 disable
phyint lo disable

# Static RP for 239.0.0.0/8 (address of the RP on the Cisco side)
rp-address 10.32.204.254 239.0.0.0/8
```

Enable and start:

```
sudo restorecon -v /etc/systemd/system/pimd.service /etc/pimd.conf
sudo systemctl daemon-reload
sudo systemctl enable --now pimd
sudo journalctl -u pimd -f
```

pimd and smcroute both need exclusive ownership of the kernel's multicast
routing socket. Run only one of them on a system (section 11.2).

---

## 9. Testing and Verification

### 9.1 Verification Commands — ESXi Host

Find the VM's switch port:

```
net-stats -l | grep -i rhel-mc01
```

Capture multicast at the VM's port:

```
pktcap-uw --switchport <PortNum> --dir 2 -o - | tcpdump-uw -enr - multicast
```

Capture IGMP leaving through an uplink:

```
pktcap-uw --uplink vmnic2 --dir 1 -o - | tcpdump-uw -enr - igmp
```

Capture group traffic arriving on an uplink:

```
pktcap-uw --uplink vmnic2 --dir 0 -o - | tcpdump-uw -enr - 'vlan 2601 and host 239.1.1.1'
```

Check uplink link state:

```
esxcli network nic list
```

Check which VLAN a standard switch port group uses:

```
esxcli network vswitch standard portgroup list
```

### 9.2 Verification Commands — RHEL Host or Guest

Interface state and address:

```
ip -br addr show ens224
```

Routing decision for the group:

```
ip route get 239.1.1.1
```

Group membership:

```
ip maddr show dev ens224
cat /proc/net/igmp
```

`/proc/net/igmp` lists each interface, the IGMP version in use (`V2` or `V3`),
and the joined groups in hexadecimal. On x86 systems the hex value is the
address with its bytes reversed, so 239.1.1.1 appears as `010101EF`. Convert
it with:

```
python3 -c "import socket,struct; print(socket.inet_ntoa(struct.pack('<I', 0x010101EF)))"
```

Expected output: `239.1.1.1`.

Capture multicast, IGMP, or one group:

```
sudo tcpdump -i ens224 -nn multicast
sudo tcpdump -i ens224 -nn igmp
sudo tcpdump -i ens224 -nn host 239.1.1.1
```

firewalld zone and rules for the interface:

```
firewall-cmd --get-zone-of-interface=ens224
sudo firewall-cmd --zone=internal --list-all
```

rp_filter for the interface:

```
sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.ens224.rp_filter
```

Kernel UDP and reverse-path counters:

```
nstat -az UdpInDatagrams UdpRcvbufErrors UdpInErrors TcpExtIPReversePathFilter
```

Multicast routes (only when smcroute `mroute` or pimd is in use):

```
ip mroute show
```

Bare metal only — bond state:

```
cat /proc/net/bonding/bond0
```

### 9.3 Worked End-to-End Test Scenario

This scenario tests multicast from a RHEL VM on an ESXi host to a physical
client on SWITCH02 Gi1/0/1, both on VLAN 2601. For a bare-metal RHEL sender,
skip steps 2 and 7 and use bond0.2601 in place of ens224.

Environment:

```
Sender:   RHEL VM rhel-mc01 on ESXI01, port group PG-VLAN2601,
          interface ens224, IP 192.168.1.10
Receiver: Physical client on SWITCH02 Gi1/0/1, VLAN 2601, IP 192.168.1.20
Group:    239.1.1.1, UDP port 5001
```

**Step 1 — Verify interface selection on the RHEL VM**

```
ip route get 239.1.1.1
```

Expected: `dev ens224`. If not, apply section 3.4 Mechanism 1.

**Step 2 — Verify the port group on ESXI01**

In vCenter, confirm the VM's second network adapter is connected to
PG-VLAN2601 and that the port group's VLAN ID is 2601.

**Step 3 — Verify the IGMP snooping querier on SWITCH01**

On SWITCH01:

```
show ip igmp snooping querier vlan 2601 detail
```

Confirm the querier address is `10.32.204.254` and the querier is active.

**Step 4 — Start the receiver on the physical client**

On the physical client:

```
mcjoin -i eth0 -p 5001 239.1.1.1
```

Leave it running.

**Step 5 — Verify the join reached SWITCH02 and SWITCH01**

On SWITCH02:

```
show ip igmp snooping groups vlan 2601
```

Gi1/0/1 should be listed for 239.1.1.1.

On SWITCH01:

```
show ip igmp snooping groups vlan 2601
```

The trunk toward SWITCH02 should be listed for 239.1.1.1. If either entry is
missing, follow [Cisco guide §8.1](MulticastReference-Cisco_r1.0.0.md#81-multicast-not-reaching-receivers).

**Step 6 — Start the sender on the RHEL VM**

```
mcjoin -i ens224 -s -p 5001 -f 1000 239.1.1.1
```

This sends one packet per second.

**Step 7 — Verify traffic is leaving the VM and the host**

On the RHEL VM:

```
sudo tcpdump -i ens224 -nn host 239.1.1.1
```

On ESXI01, at the VM's port and at the uplink:

```
pktcap-uw --switchport <PortNum> --dir 0 -o - | tcpdump-uw -enr - host 239.1.1.1
pktcap-uw --uplink vmnic2 --dir 1 -o - | tcpdump-uw -enr - 'vlan 2601 and host 239.1.1.1'
```

If the uplink capture is empty, check the other uplink (`vmnic3`); the teaming
policy decides which one carries the VM's traffic.

**Step 8 — Verify receipt at the physical client**

The mcjoin receiver on the client should show its received-packet count rising
by about one per second.

**Step 9 — Test the reverse direction**

Swap roles: run `mcjoin -i eth0 -s -p 5001 -f 1000 239.1.1.1` on the client and
`mcjoin -i ens224 -p 5001 239.1.1.1` on the RHEL VM. If the client-to-VM
direction fails while VM-to-client works, the cause is almost always on the
receiving side: firewalld (section 3.5), rp_filter (section 11.3), or the
VM's join leaving the wrong interface (section 3.4).

**Expected successful flow (VM to client):**

```
RHEL VM sends UDP to 239.1.1.1 on ens224
    ↓ vmxnet3 vNIC → PG-VLAN2601
    ↓ ESXi uplink vmnic2, tagged VLAN 2601
    ↓ SWITCH01 (snooping table lists the trunk to SWITCH02 for 239.1.1.1)
    ↓ SWITCH01 → SWITCH02 trunk
    ↓ SWITCH02 (snooping table lists Gi1/0/1 for 239.1.1.1)
    ↓ Gi1/0/1
    ↓ Physical client receives the packet
```

---

## 10. Troubleshooting

### 10.1 Multicast Not Leaving the RHEL System

Symptom: tcpdump on ens224 (or bond0.2601) shows no outbound multicast while the
sender is running.

Step 1 — Verify the interface is up:

```
ip link show ens224
```

It must show `UP` and `LOWER_UP`. On bare metal also check the VLAN parent:
`ip link show bond0` and `cat /proc/net/bonding/bond0`.

Step 2 — Verify the interface has an IPv4 address:

```
ip -br addr show ens224
```

Without an address the interface cannot be the source of IPv4 multicast.

Step 3 — Verify the kernel selects the right interface:

```
ip route get 239.1.1.1
```

If it shows another interface, capture there: the traffic is probably leaving
through the management interface. Apply section 3.4.

Step 4 — Verify the sender names the interface or source address (`-i` in
mcjoin, `-B <ip>` in iperf, `ip-multicast-if` in socat).

Step 5 — Check the TTL. A TTL of 0 keeps the packet on the local host. The
sender must use TTL 1 or higher.

Step 6 — Check for an outbound firewall rule. firewalld does not filter
outbound traffic by default, but a site policy might:

```
sudo nft list ruleset | grep -iE 'output|239\.'
```

### 10.2 Multicast Not Arriving at the RHEL System

Symptom: the sender is running and the switch has a membership entry for the
RHEL system's port, but the application on RHEL receives nothing.

Step 1 — Check whether frames reach the interface:

```
sudo tcpdump -i ens224 -nn host 239.1.1.1
```

tcpdump sees packets before firewalld and rp_filter. If packets appear here but
not in the application, go to step 3. If nothing appears, go to step 2.

Step 2 — Nothing in tcpdump:

- VMware: capture at the uplink and at the VM's switch port (section 9.1). If
  the uplink has the traffic but the VM's port does not, check the port group
  VLAN ID and the vDS multicast filtering mode (section 2.2). In snooping mode
  confirm the VM's IGMP report reached the vDS (step 1 of section 10.3).
- Bare metal: confirm the VLAN interface exists on the right parent and ID:
  `ip -d link show bond0.2601`.
- Both: check the switch snooping table for the RHEL system's port
  (`show ip igmp snooping groups vlan 2601`).

Step 3 — Packets in tcpdump but not in the application. Check firewalld:

```
firewall-cmd --get-zone-of-interface=ens224
sudo firewall-cmd --zone=<zone> --list-all
```

The UDP port must be allowed (section 3.5). To confirm firewalld is the cause,
temporarily allow the port at runtime only (no `--permanent`):

```
sudo firewall-cmd --zone=<zone> --add-port=5001/udp
```

Step 4 — Check rp_filter:

```
sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.ens224.rp_filter
nstat -az TcpExtIPReversePathFilter
```

If the effective value is 1 (strict) and the sender's address is not reachable
through ens224 according to the routing table, the kernel drops the packets and
the counter rises. See section 11.3.

Step 5 — Check that the application joined on the right interface:

```
ip maddr show dev ens224
cat /proc/net/igmp
```

If the group is listed on another interface, see section 3.4.

Step 6 — Check for socket buffer overflow at high rates:

```
nstat -az UdpRcvbufErrors
```

A rising count means the application is not reading fast enough. See section
11.8.

### 10.3 IGMP Join Not Seen by Switch

Symptom: the RHEL system has joined a group, but
`show ip igmp snooping groups vlan 2601` on SWITCH01 does not list its port.

Step 1 — Confirm the report leaves the RHEL system:

```
sudo tcpdump -i ens224 -nn igmp
```

Restart the receiver while capturing. You should see a membership report for
the group. If it appears on another interface, see section 3.4. If no report
appears at all, the application or smcroute did not join.

Step 2 — VMware: confirm the report reaches the uplink:

```
pktcap-uw --uplink vmnic2 --dir 1 -o - | tcpdump-uw -enr - igmp
pktcap-uw --uplink vmnic3 --dir 1 -o - | tcpdump-uw -enr - igmp
```

The frame should carry 802.1Q tag 2601.

Step 3 — Bare metal: confirm the report leaves the bond tagged:

```
sudo tcpdump -i bond0 -nn -e igmp
```

The frame should show `vlan 2601`.

Step 4 — Check the IGMP version. The Cisco side defaults to IGMPv2 on SVIs.
RHEL sends IGMPv3 reports unless it hears a v2 querier. Both work for
any-source groups, but if the switch is configured for v2 only and the RHEL
system has `force_igmp_version` set to 3, the switch may ignore its reports:

```
sysctl net.ipv4.conf.ens224.force_igmp_version
grep -A1 ens224 /proc/net/igmp
```

`0` means automatic (recommended).

### 10.4 Multicast Works Briefly Then Stops

Symptom: delivery works after the join but stops after a few minutes, usually
about 260 seconds.

This is almost always a membership timeout: the switch is not receiving
refreshed reports. With Cisco defaults the membership interval is
2 × 125 s query interval + 10 s maximum response time = 260 s.

Step 1 — Verify the querier is active on SWITCH01:

```
show ip igmp snooping querier vlan 2601 detail
```

Step 2 — Verify general queries reach the RHEL interface:

```
sudo tcpdump -i ens224 -nn igmp
```

Within about two minutes you should see a query from 10.32.204.254 and the RHEL
system's report in response.

Step 3 — Queries appear in tcpdump but no report follows: the queries are being
dropped by firewalld before the kernel processes them (tcpdump sees packets
before the firewall). Allow IGMP in the interface's zone:

```
sudo firewall-cmd --permanent --zone=<zone> --add-protocol=igmp
sudo firewall-cmd --reload
```

This is the most common cause of this symptom on RHEL.

Step 4 — No queries in tcpdump: the querier is not active, or queries are not
reaching this VLAN or port. On VMware, check the uplink capture for queries
(`--dir 0`). See [Cisco guide §3](MulticastReference-Cisco_r1.0.0.md#3-igmp-snooping).

Step 5 — The join was held by smcroute or an application that has exited. The
kernel only answers queries for groups that an open socket (or an `autojoin`
address) still holds:

```
systemctl status smcroute
cat /proc/net/igmp
```

### 10.5 VM Receiving Groups It Did Not Join

Symptom: a RHEL VM's tcpdump shows traffic for groups it never joined.

This is expected in vSphere basic filtering mode when groups share a multicast
MAC address (section 2.2). For example 239.1.1.1 and 239.129.1.1 both map to
01:00:5e:01:01:01. The kernel discards the unjoined groups before they reach
any socket, so applications are not affected.

Step 1 — Check whether the unexpected groups share the MAC of a joined group:

```
sudo tcpdump -i ens224 -nn -e multicast
```

Step 2 — If the extra traffic costs too much CPU, either renumber groups so
they do not share MACs, or switch the vDS to IGMP/MLD snooping mode.

Step 3 — If the unexpected traffic is in a different VLAN, the VM's port group
has the wrong VLAN ID, or the port group uses VLAN trunking (4095).

### 10.6 Multicast Interrupted After vMotion or Uplink Failover

Symptom: a RHEL VM stops receiving multicast after it is migrated with vMotion,
or after an ESXi uplink fails, and recovers on its own within about two
minutes.

After a vMotion or a failover between independent uplinks, the VM's traffic
enters the physical network on a different switch port. ESXi sends RARP frames
so the switch learns the VM's MAC on the new port, but the switch's IGMP
snooping table still lists the old port. Delivery resumes when the next general
query arrives and the VM reports again on the new port (up to one query
interval, 125 s by default).

Options to reduce the gap:

- Use a port-channel (vDS LAG or IP hash with static EtherChannel) so an uplink
  failure does not move the VM to a different logical port (section 2.5).
- Lower the IGMP query interval on the SWITCH01 querier for VLAN 2601.
- Have the application or smcroute re-join after migration. For smcroute:
  `sudo systemctl restart smcroute` sends fresh reports immediately.

Verify recovery timing by running mcjoin as a receiver during a test vMotion
and noting when the packet count resumes.

---

## 11. Deep Dive — Advanced Multicast Interface Control

This section covers kernel and NetworkManager mechanisms for controlling
multicast interface selection and behavior on RHEL 9 and RHEL 10. It goes beyond
the operational configuration in sections 1–10 and is a reference for complex
multi-homed designs and hard-to-diagnose failures. It applies to bare metal and
VMware guests alike unless stated.

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
`from` rule never matches that lookup. For default membership-interface selection, inspect the applicable lookup;
an explicit membership interface avoids dependence on a blanket 239/8 route.

**Example: a dedicated table for VLAN 2601.**

Create a table with a multicast route and a connected route, and a rule that
sends traffic from the VLAN 2601 address to it:

```
sudo nmcli connection modify ens224 \
    ipv4.routes "192.168.1.0/24 table=2601, 239.0.0.0/8 table=2601, 239.0.0.0/8" \
    ipv4.routing-rules "priority 100 from 192.168.1.10 table 2601"
sudo nmcli connection up ens224
```

The `239.0.0.0/8` entry without `table=` stays in `main` for joins. Tables can
be referred to by number alone. A name is optional and cosmetic; to add one,
create `/etc/iproute2/rt_tables.d/multicast.conf` containing `2601 vlan2601`.

Verify:

```
ip rule show
ip route show table 2601
ip route get 239.1.1.1 from 192.168.1.10
```

**Example: marking traffic for one application.** If an application cannot bind
to a source address, mark its packets with nftables by cgroup or UID and route
by mark (`ip rule add fwmark 0x2601 table 2601`). This is complex and rarely
needed; prefer binding in the application.

**Interaction with rp_filter.** In strict mode, rp_filter checks the reverse
path using the full policy routing decision for the received packet (as if
replying from the receiving interface). A rule that routes the sender's subnet
through a different table can make strict mode pass or fail unexpectedly. Test
with:

```
ip route get 192.168.1.20 from 192.168.1.10 iif ens224
```

A result with `dev ens224` passes strict reverse-path filtering.

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
(192.168.1.20,239.1.1.1)  Iif: bond0.2601  Oifs: bond0.2602  State: resolved
```

Rules the kernel applies when forwarding:

- A packet is forwarded only if it arrives on the entry's inbound interface.
  Packets arriving elsewhere are not forwarded (and pimd treats them as an RPF
  failure).
- A packet is never forwarded back out of its inbound interface.
- Each outbound VIF has a TTL threshold. A packet is forwarded only if its TTL
  is greater than the threshold, and TTL is decremented on forwarding. Senders
  with TTL 1 are never forwarded.
- If no MFC entry matches, the kernel notifies the daemon (an "upcall"). pimd
  may then create an entry. smcroute creates entries for wildcard-source
  `mroute` lines on demand.

`net.ipv4.conf.all.mc_forwarding` reads `1` while a daemon holds the multicast
routing socket. It is read-only and set by the kernel.

Only one process can own the multicast routing socket for a routing table.
Starting pimd while smcroute is running (or the reverse) fails with an
"address in use" error in the log. Linux supports multiple multicast routing
tables (one per VRF, for example) for separate daemon instances; check that
the running kernel was built with `CONFIG_IP_MROUTE_MULTIPLE_TABLES` before
relying on it:

```
grep IP_MROUTE /boot/config-$(uname -r)
```

In this intra-VLAN environment the MFC is empty and should stay empty. A
non-empty `ip mroute show` on a host that is not meant to route multicast means
a routing daemon is running that should not be.

### 11.3 rp_filter — Reverse Path Filtering

Reverse path filtering drops a received IPv4 packet if the packet's source
address is not reachable back through the interface it arrived on. It applies to
multicast data the same way as to unicast. It is a frequent cause of
"tcpdump shows the traffic but the application gets nothing" on multi-homed
systems.

Values:

| Value | Mode   | Check                                                         |
|-------|--------|---------------------------------------------------------------|
| 0     | Off    | No check                                                      |
| 1     | Strict | The best route back to the source must use the receiving interface |
| 2     | Loose  | The source must be reachable through any interface            |

**The effective value is the higher of `net.ipv4.conf.all.rp_filter` and
`net.ipv4.conf.<interface>.rp_filter`.** Setting the interface to 2 makes it
loose whatever `all` is. With interface=1, all=0 keeps strict mode,
whereas all=2 makes the effective mode loose. Setting only the interface to 0
cannot disable filtering when all remains nonzero.

Check every value on the system:

```
sysctl -a 2>/dev/null | grep '\.rp_filter'
```

Do not assume a default. The value can come from the kernel, from
`/usr/lib/sysctl.d/`, from `/etc/sysctl.d/`, or from a hardening baseline, and
differs between builds and sites. Read it on each system.

**How strict mode breaks multicast.** The sender 192.168.1.20 is on VLAN 2601.
If the RHEL system's route to 192.168.1.0/24 is via ens224, strict mode passes.
It fails when:

- The sender is on another subnet (routed multicast) and the route back to it
  is via the management interface's default route.
- The sender's address is outside the subnet configured on ens224 (for example
  a device with a misconfigured or link-local source address).
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
`/etc/sysctl.d/90-multicast.conf`:

```
net.ipv4.conf.ens224.rp_filter = 2
```

Because the higher value wins, this works whether `all` is 0, 1 or 2. Do not
set the interface to 0 to disable the check: if `all` is 1, the effective value
stays 1.

Apply:

```
sudo sysctl -p /etc/sysctl.d/90-multicast.conf
```

**VLAN interfaces with a dot in the name.** In sysctl keys the dot is the
separator, so the interface `bond0.2601` is written with a slash:

```
sysctl net.ipv4.conf.bond0/2601.rp_filter
```

In files under `/etc/sysctl.d/`, use the same slash form:

```
net.ipv4.conf.bond0/2601.rp_filter = 2
```

A per-interface key only applies once the interface exists. For VLAN or bond
interfaces created by NetworkManager after `systemd-sysctl` has run, systemd
reapplies matching keys when the interface appears, but verify after reboot.


### 11.4 igmp_max_memberships and Related Limits

`net.ipv4.igmp_max_memberships` limits how many groups **one socket** can join.
The default is 20. A join beyond the limit fails with `ENOBUFS`
("No buffer space available"), which applications often report misleadingly as
a memory problem.

Related limits:

| Sysctl                          | Default | Limits                                                  |
|---------------------------------|---------|---------------------------------------------------------|
| net.ipv4.igmp_max_memberships   | 20      | Groups per IPv4 socket                                  |
| net.ipv4.igmp_max_msf           | 10      | Sources per IPv4 source filter (SSM include/exclude list) |
| net.core.optmem_max             | varies  | Per-socket option memory; very large source lists can hit it |

There is no host-wide group limit in the kernel: many sockets can each join up
to the per-socket limit. Host-wide limits come from elsewhere:

- The NIC's hardware multicast filter. When a NIC runs out of filter slots the
  driver puts it in all-multicast mode. This is correct but costs CPU. Check
  with `ip -d link show ens224` (look for `ALLMULTI`) and `ethtool -S`.
- The switch's IGMP snooping table, and on VMware the vDS snooping table in
  IGMP/MLD snooping mode.

Raise the per-socket limit when one application must join many groups. Persist
in `/etc/sysctl.d/90-multicast.conf`:

```
net.ipv4.igmp_max_memberships = 256
```

Apply with `sudo sysctl -p /etc/sysctl.d/90-multicast.conf`. Already-open
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

Create a VRF with NetworkManager and move the multicast interface into it:

```
sudo nmcli connection add type vrf con-name vrf-mc ifname vrf-mc table 1001 \
    ipv4.method disabled ipv6.method disabled
sudo nmcli connection modify ens224 master vrf-mc
sudo nmcli connection up vrf-mc
sudo nmcli connection up ens224
```

The routes configured on ens224 (including 239.0.0.0/8) are now installed in
table 1001. Verify:

```
ip -d link show vrf-mc
ip route show vrf vrf-mc
ip route get vrf vrf-mc 239.1.1.1
```

Run a tool inside the VRF:

```
sudo ip vrf exec vrf-mc mcjoin -i ens224 -p 5001 239.1.1.1
```

`ip vrf exec` works by attaching a BPF program to a cgroup and needs cgroup v2,
which is the default on RHEL 9 and RHEL 10.

Applications can instead bind their socket to the VRF device with
`SO_BINDTODEVICE`. For unbound UDP sockets in the default VRF to receive
packets that arrive on VRF interfaces, set:

```
net.ipv4.udp_l3mdev_accept = 1
```

Only do this if that cross-VRF receive is intended.

Run smcroute for VRF interfaces with the unit's `ExecStart` wrapped in
`ip vrf exec vrf-mc`, so its `mgroup` sockets belong to the VRF. For
forwarding (`mroute`) inside a VRF, the daemon must use the VRF's multicast
routing table, which needs multiple-table support (section 11.2) and daemon
support; test before relying on it.

### 11.6 smcroute Interface Binding in Multi-Interface Environments

`mgroup` and `mroute` lines always name their interfaces explicitly. smcroute
does not use the routing table to choose an interface. A join on the wrong
interface is a silent configuration error: smcroute logs no error, and the IGMP
report simply appears on that interface.

Join the same group on two interfaces (two VLANs) — one line per interface:

```
mgroup from ens224 group 239.1.1.1
mgroup from ens256 group 239.1.1.1
```

Source-specific join:

```
mgroup from ens224 group 239.1.1.4 source 192.168.1.20
```

Interfaces that do not exist at startup are skipped with a log message. If a
VLAN interface is created later by NetworkManager, reload smcroute to retry the
joins:

```
sudo systemctl reload smcroute
```

Verify where each group is joined:

```
sudo smcroutectl show groups
ip maddr show dev ens224
ip maddr show dev ens256
```

Interaction with the 239.0.0.0/8 route from section 3.4: none for `mgroup`. The
route affects only applications that do not name an interface. A host with both
can therefore join a group on ens256 through smcroute while an application's
own unnamed join of the same group goes out ens224. Name interfaces everywhere.

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
phyint bond0.200 disable
phyint bond0.2601 enable
phyint bond0.2602 enable
phyint lo disable
```

Newer pimd versions also support a global `no phyint` directive to start with
all interfaces disabled; check `man pimd.conf` for the installed version.

Interaction with rp_filter: pimd does its own RPF check against the unicast
routing table to choose the inbound interface for each source. If kernel
rp_filter is strict and the unicast route back to a source points at a
different interface, the kernel drops packets before pimd sees them. Use loose
mode (section 11.3) on PIM interfaces.

Verify pimd's interface state with `pimctl` (installed with pimd 3.x):

```
sudo pimctl show interface
sudo pimctl show neighbor
sudo pimctl show igmp
```

With older versions, run pimd in the foreground with debug output:

```
sudo pimd -n -d
```

### 11.8 Socket-Level Controls — IP_MULTICAST_ALL and Receive Buffers

Two socket-level behaviors cause hard-to-diagnose problems in receivers that
bind to a port rather than to a group.

**IP_MULTICAST_ALL.** Linux enables this socket option by default. A UDP socket
bound to `0.0.0.0:5001` then receives traffic for **every** group joined by
**any** socket on the host on port 5001 — not only the groups it joined itself.
Two applications on one host that use the same port for different groups
receive each other's traffic.

Mitigations, in order of preference:

1. The application binds to the group address (`239.1.1.1:5001`) instead of
   `0.0.0.0:5001`.
2. The application sets `IP_MULTICAST_ALL` to 0 on its socket
   (IPv4 coverage only).
3. Use different ports for different groups.

There is no system-wide sysctl for this option.

**Receive buffers.** A socket's receive buffer absorbs bursts while the
application is busy. If it fills, the kernel drops packets and increments
`UdpRcvbufErrors`:

```
nstat -az UdpRcvbufErrors Udp6RcvbufErrors
```

A rising count with traffic visible in tcpdump means drops are local to the
host.

An application's requested buffer size (`SO_RCVBUF`) is silently capped at
`net.core.rmem_max`. Check the current limits:

```
sysctl net.core.rmem_max net.core.rmem_default
```

Raise the cap (and optionally the default) for high-rate multicast receivers.
Persist in `/etc/sysctl.d/90-multicast.conf`:

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

### 11.9 Deep Dive Troubleshooting

Failures that occur only when the mechanisms in sections 11.1–11.8 are in use.
Basic troubleshooting is in section 10.

**Policy routing sends joins out the wrong interface.**
Symptom: sends from the bound source address go out ens224, but the IGMP join
for a receiver goes out ens192.
Cause: `from` rules do not match the join lookup (section 11.1).
Check: `ip route get 239.1.1.1` (no `from`).
Fix: keep 239.0.0.0/8 in the `main` table, or have the application name the
interface in its join.

**Stale or unexpected MFC entries.**
Symptom: multicast is duplicated onto another VLAN, or a host forwards traffic
it should not.
Check: `ip mroute show` and `systemctl status smcroute pimd`.
Fix: remove the unintended `mroute` lines or stop the routing daemon. On a host
that should not route multicast, the MFC must be empty.

**rp_filter drops with no obvious log entry.**
Symptom: traffic in tcpdump, nothing in the application, firewalld correct.
Check: `nstat -az TcpExtIPReversePathFilter` rising; effective value =
max(`all`, interface).
Fix: loose mode (section 11.3), or fix the unicast route to the sender's
subnet.

**igmp_max_memberships exhausted.**
Symptom: the first 20 groups work; later joins fail with "No buffer space
available" (ENOBUFS) in the application log, while other applications on the
host still join fine.
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
Fix: `After=network-online.target` and `Wants=network-online.target` in the
unit, `NetworkManager-wait-online.service` enabled, or reload smcroute from a
NetworkManager dispatcher script when the interface comes up.

**pimd took over the querier role.**
Symptom: intermittent multicast loss that coincides with pimd restarts or host
reboots; `show ip igmp snooping querier vlan <id>` on SWITCH01 shows the RHEL
host's address.
Fix: `phyint <interface> disable` for every interface that is not a PIM
interface (section 11.7).

**VRF application cannot join or receive.**
Symptom: the application works outside the VRF but not when the interface is
moved into it.
Check: is the application running under `ip vrf exec` or bound to the VRF
device? `ip route get vrf vrf-mc 239.1.1.1` shows the expected interface?
Fix: start the application in the VRF; add the 239.0.0.0/8 route to the VRF's
connection; set `udp_l3mdev_accept` only if cross-VRF receive is intended.

**Two applications receive each other's groups.**
Symptom: an application reports unexpected packets or parse errors after another
multicast application starts on the same host.
Cause: `IP_MULTICAST_ALL` with sockets bound to `0.0.0.0` on the same port
(section 11.8).
Fix: bind to the group address, disable the option in the application, or use
distinct ports.

**Receive drops at high rate.**
Symptom: loss reported by the application or iperf server; the switch and
tcpdump show complete traffic.
Check: `nstat -az UdpRcvbufErrors`, `ss -uamn`, and `sysctl net.core.rmem_max`.
Fix: raise `rmem_max` and the application's buffer request (section 11.8); on
VMware, check the VM's vCPU contention (CPU ready time) in vCenter.

---

## 12. Glossary

| Term                 | Definition                                                                    |
|----------------------|-------------------------------------------------------------------------------|
| 239.0.0.0/8          | Administratively scoped multicast range. Administratively scoped; configured boundaries enforce scope.  |
| autojoin             | `ip addr add` flag that makes the kernel join a multicast address on an interface. |
| Basic multicast filtering | vSphere switch mode that forwards multicast by destination MAC from the guest's filter list. |
| bond0                | LACP 802.3ad bond on bare-metal RHEL servers providing the uplink to SWITCH01. |
| CodeReady Builder    | RHEL repository of build dependencies; required by EPEL.                      |
| EPEL                 | Extra Packages for Enterprise Linux. Fedora-maintained add-on repository.     |
| ESXi                 | VMware's hypervisor, running on each vSphere host.                            |
| firewalld            | Default RHEL firewall service; manages nftables rules by zone.                |
| IGMP                 | Internet Group Management Protocol. Used by hosts to join multicast groups.   |
| IGMP Snooping        | Switch feature that tracks multicast membership per port.                     |
| igmp_max_memberships | Kernel parameter: maximum groups per socket. Default 20.                      |
| IP_MULTICAST_ALL     | Socket option (on by default) that delivers all joined groups on a port to wildcard-bound sockets. |
| iperf (iperf2)       | Network test tool with multicast UDP support. Package `iperf` in EPEL.        |
| iperf3               | Network test tool. Does not support multicast.                                |
| ip maddr             | Linux command showing multicast memberships per interface.                    |
| ip route get         | Linux command showing which route and interface the kernel selects.           |
| ip rule              | Linux command managing policy routing rules.                                  |
| Intra-VLAN           | Traffic within a single VLAN requiring no routing.                            |
| LAG                  | Link Aggregation Group. On a vDS, an LACP bundle of uplinks.                  |
| mcjoin               | Minimal multicast join and send tool for testing. Built from source on RHEL.  |
| MFC                  | Multicast Forwarding Cache. Kernel table used when forwarding multicast.      |
| Multi-homed          | A machine with more than one active network interface.                        |
| net-stats            | ESXi command that lists switch ports and their clients.                       |
| NetworkManager       | RHEL network configuration service; configured with `nmcli`.                  |
| never-default        | NetworkManager setting that stops a connection installing a default route.    |
| nmcli                | NetworkManager command-line client.                                           |
| pimd                 | PIM-SM/SSM routing daemon. For routed multicast environments only.            |
| PIM-SM               | Protocol Independent Multicast Sparse Mode.                                   |
| pktcap-uw            | ESXi packet capture tool for switch ports and uplinks.                        |
| Port group           | vSphere switch object that sets VLAN, teaming and security for attached vNICs.|
| rp_filter            | Reverse path filtering. Drops packets whose source is not reachable via the receiving interface. |
| SELinux              | Mandatory access control system, enforcing by default on RHEL.                |
| smcroute             | Static multicast join and routing daemon. Built from source on RHEL.          |
| socat                | General-purpose relay tool; usable as a multicast sender and receiver.        |
| tcpdump              | Command-line packet capture tool.                                             |
| tshark               | Command-line Wireshark (package `wireshark-cli`).                             |
| vDS                  | vSphere Distributed Switch, managed by vCenter across hosts.                  |
| VGT                  | Virtual Guest Tagging: the guest handles 802.1Q tags (port group VLAN 4095).   |
| vmxnet3              | VMware paravirtual NIC; the recommended vNIC type for RHEL guests.            |
| VRF                  | Virtual Routing and Forwarding. Isolated routing table bound to interfaces.   |
| vSS                  | vSphere Standard Switch, configured per host.                                 |
| VST                  | Virtual Switch Tagging: the port group adds the VLAN tag.                     |

## Appendix A — Acronyms and meanings

Literal command/API identifiers, interface names and lab device names are not
acronyms. Product names (such as IOS XE, ESXi and VirtIO) identify platforms;
use the vendor documentation for their release-specific behavior.

| Term | Meaning |
|---|---|
| AVC | Access Vector Cache (SELinux audit messages) |
| CPU | Central Processing Unit |
| DHCP | Dynamic Host Configuration Protocol |
| EPEL | Extra Packages for Enterprise Linux |
| EST | External Switch Tagging |
| ID | Identifier |
| IGMP | Internet Group Management Protocol |
| IP | Internet Protocol |
| IPv4 | Internet Protocol version 4 |
| IPv6 | Internet Protocol version 6 (outside this guide's configuration coverage) |
| LACP | Link Aggregation Control Protocol |
| LAG | Link Aggregation Group |
| MAC | Media Access Control |
| MFC | Multicast Forwarding Cache |
| MLD | Multicast Listener Discovery (outside this guide's configuration coverage) |
| NIC | Network Interface Card |
| OS | Operating System |
| PIM | Protocol Independent Multicast |
| PIM-SM | Protocol Independent Multicast — Sparse Mode |
| PIM-SSM | Protocol Independent Multicast for Source-Specific Multicast |
| RHEL | Red Hat Enterprise Linux |
| RP | Rendezvous Point |
| RPF | Reverse Path Forwarding |
| SELinux | Security-Enhanced Linux |
| SM | Sparse Mode |
| SSH | Secure Shell |
| SSM | Source-Specific Multicast |
| TTL | Time to Live |
| UDP | User Datagram Protocol |
| UID | User Identifier |
| vCPU | Virtual Central Processing Unit |
| vDS | vSphere Distributed Switch |
| VGT | Virtual Guest Tagging |
| VIF | Virtual Interface (multicast forwarding context) |
| VLAN | Virtual Local Area Network |
| VM | Virtual Machine |
| vNIC | Virtual Network Interface Card |
| VRF | Virtual Routing and Forwarding |
| vSS | vSphere Standard Switch |
| VST | Virtual Switch Tagging |
| ALLMULTI | All-multicast receive flag (interface setting) |
| BPF | Berkeley Packet Filter |
| MII | Media Independent Interface |
| RARP | Reverse Address Resolution Protocol |

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
| R1 | [firewalld configuration manual](https://firewalld.org/documentation/man-pages/firewalld.conf.html) | Policy/backend configuration; no blanket packet-accept/drop conclusion |
| R2 | [firewall-cmd manual](https://firewalld.org/documentation/man-pages/firewall-cmd.html) | Zone/rule inspection and modification commands |
| R3 | [Red Hat Using SELinux](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_selinux/index) | Policy/domain/label inspection; no universal custom-service domain assumed |
| R4 | [Broadcom multicast filtering-mode article](https://knowledge.broadcom.com/external/article/380617/changing-multicast-filtering-mode-on-dis.html) | Basic versus IGMP/MLD product modes; this article is not vSphere 9 qualification |
| R5 | [Fedora mcjoin package index](https://packages.fedoraproject.org/pkgs/mcjoin/mcjoin/) | Package availability must be checked per repository/release; Fedora is not proof of EPEL availability |
| G1 | [RFC 2365 — Administratively Scoped IP Multicast](https://www.rfc-editor.org/rfc/rfc2365.html) | 239/8 scope requires configured administrative boundaries; it is not inherent authentication or isolation |

### Qualification still required

| Evidence | Status |
|---|---|
| Exact OS/device/software versions and effective policy | Record and test at the site |
| Commands/scripts and complete data path | Not executed during this review |
| Throughput, loss, failover and recovery | Not measured; examples are not guarantees |
| IPv6/MLD | Explicitly outside this guide |
| vSphere 9 switch/UI/capture behavior | Verify deployed build; older/general source material is not a vSphere 9 test |
