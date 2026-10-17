# Multicast Reference Guide — Cisco Catalyst 9200 / 9300

| Field          | Detail                          |
|----------------|---------------------------------|
| Version        | 1.0.0                           |
| Last Updated   | 20250517                        |
| Author         | sysadmin                        |
| Filename       | MulticastReference-Cisco_r1.0.0.md |

---

## Revision History

| Version | Date     | Author    | Change Summary  |
|---------|----------|-----------|-----------------|
| 1.0.0   | 20250517 | sysadmin  | Initial release |

---

## Table of Contents

1. [Overview](#1-overview)
2. [Multicast Fundamentals](#2-multicast-fundamentals)
   - 2.1 [How IP Multicast Works](#21-how-ip-multicast-works)
   - 2.2 [IGMP Versions](#22-igmp-versions)
   - 2.3 [Multicast Address Ranges](#23-multicast-address-ranges)
3. [IGMP Snooping](#3-igmp-snooping)
   - 3.1 [What IGMP Snooping Does](#31-what-igmp-snooping-does)
   - 3.2 [Default Behavior on IOS-XE](#32-default-behavior-on-ios-xe)
   - 3.3 [Querier Role and Election](#33-querier-role-and-election)
   - 3.4 [Querier Source Address Selection](#34-querier-source-address-selection)
   - 3.5 [Theoretical Scenarios](#35-theoretical-scenarios)
4. [Layer 2 Only Switch — Access Layer (SWITCH02 Style)](#4-layer-2-only-switch--access-layer-switch02-style)
   - 4.1 [Characteristics](#41-characteristics)
   - 4.2 [Recommended Configuration](#42-recommended-configuration)
   - 4.3 [Verification Commands](#43-verification-commands)
5. [Aggregation Switch — Mixed L2/L3 (SWITCH01 Style)](#5-aggregation-switch--mixed-l2l3-switch01-style)
   - 5.1 [Characteristics](#51-characteristics)
   - 5.2 [Impact of ip multicast-routing on L2 VLANs](#52-impact-of-ip-multicast-routing-on-l2-vlans)
   - 5.3 [Recommended Configuration](#53-recommended-configuration)
   - 5.4 [Verification Commands](#54-verification-commands)
6. [Spanning Tree Interaction with Multicast](#6-spanning-tree-interaction-with-multicast)
   - 6.1 [TCN-Triggered Multicast Table Flushing](#61-tcn-triggered-multicast-table-flushing)
   - 6.2 [PortFast Interaction](#62-portfast-interaction)
   - 6.3 [BPDU Guard Interaction](#63-bpdu-guard-interaction)
   - 6.4 [Recommended Spanning Tree Settings for Multicast Ports](#64-recommended-spanning-tree-settings-for-multicast-ports)
7. [RSPAN Interaction with Multicast](#7-rspan-interaction-with-multicast)
   - 7.1 [General Risk](#71-general-risk)
   - 7.2 [Worked Example — VLAN 50 and 239.x.x.x](#72-worked-example--vlan-50-and-239xxx)
   - 7.3 [Mitigation](#73-mitigation)
8. [Troubleshooting](#8-troubleshooting)
   - 8.1 [Multicast Not Reaching Receivers](#81-multicast-not-reaching-receivers)
   - 8.2 [Multicast Flooding to All Ports](#82-multicast-flooding-to-all-ports)
   - 8.3 [Querier Election Conflicts](#83-querier-election-conflicts)
   - 8.4 [Multicast Disrupted After Topology Change](#84-multicast-disrupted-after-topology-change)
9. [Glossary](#9-glossary)

---

## 1. Overview

This document is a reference guide for configuring and troubleshooting Layer 2
multicast on Cisco Catalyst 9200 and 9300 series switches running IOS-XE. It
covers two distinct switch roles: a pure access layer switch with no IP routing
and no SVIs on data VLANs, and an aggregation switch with IP routing enabled and
a mixed SVI environment. It addresses IGMP snooping, querier configuration,
spanning tree interactions, and RSPAN interactions with multicast.

The environment this guide is based on uses intra-VLAN multicast only. VMs
running on Proxmox servers communicate with physical clients on the same VLAN
via SWITCH01 and SWITCH02. No inter-VLAN multicast routing is required. Multicast
group addresses are assumed to be in the 239.0.0.0/8 private range.

---

## 2. Multicast Fundamentals

### 2.1 How IP Multicast Works

IP multicast allows a single sender to reach multiple receivers efficiently by
sending one stream that the network replicates only where needed. Unlike unicast
(one-to-one) or broadcast (one-to-all), multicast is one-to-many but delivered
only to interested receivers.

Key components:

```
Sender → multicast group address (e.g. 239.1.1.1)
         ↓
         Switch replicates frame only to ports where receivers have joined
         ↓
         Receivers that have sent IGMP join for 239.1.1.1
```

At Layer 2, multicast MAC addresses are derived from the multicast IP address.
The low 23 bits of the IP address map into the MAC range 01:00:5e:00:00:00 to
01:00:5e:7f:ff:ff. Because only 23 bits map into a 28-bit IP multicast space,
32 IP multicast groups share each L2 multicast MAC address. This is relevant
for IGMP snooping because the switch tracks group membership at the IP level,
not the MAC level.

### 2.2 IGMP Versions

| Version | Key Feature                                      | Recommended Use     |
|---------|--------------------------------------------------|---------------------|
| IGMPv1  | Basic join only, no leave mechanism              | Legacy only         |
| IGMPv2  | Adds leave group message, faster leave           | Minimum recommended |
| IGMPv3  | Source-specific multicast, include/exclude modes | Preferred           |

IOS-XE defaults to IGMPv2 on SVIs. Explicit configuration of IGMPv3 is
recommended where the end devices support it.

### 2.3 Multicast Address Ranges

| Range                     | Purpose                                      |
|---------------------------|----------------------------------------------|
| 224.0.0.0/24              | Link-local, not forwarded by routers         |
| 224.0.1.0 – 238.255.255.255 | Globally scoped, routable                 |
| 239.0.0.0/8               | Administratively scoped, private use         |
| 240.0.0.0/4               | Reserved                                     |

For intra-VLAN multicast in a private lab or enterprise environment, the
239.0.0.0/8 range is the correct choice. These addresses are analogous to RFC
1918 private unicast addresses — they are not routed on the public internet and
are intended for organizationally scoped use.

---

## 3. IGMP Snooping

### 3.1 What IGMP Snooping Does

IGMP snooping is a Layer 2 optimization that allows a switch to listen to IGMP
traffic between hosts and routers and build a table of which ports have active
multicast group members. Without IGMP snooping, the switch would treat multicast
frames like broadcasts and flood them to every port in the VLAN.

With IGMP snooping enabled, the switch:

- Listens to IGMP general queries sent by the querier
- Listens to IGMP membership reports sent by hosts joining groups
- Listens to IGMP leave messages sent by hosts leaving groups
- Builds a per-VLAN, per-group membership table keyed to specific ports
- Forwards multicast frames only to ports that have active members

### 3.2 Default Behavior on IOS-XE

On Catalyst 9200 and 9300, IGMP snooping is enabled globally by default. No
explicit configuration is required to enable it. However default behavior without
a querier configured is to flood multicast to all ports in the VLAN, because
without queries there are no membership reports to snoop on.

Verify global IGMP snooping status:

```
show ip igmp snooping
```

Verify per-VLAN IGMP snooping status:

```
show ip igmp snooping vlan 2601
```

### 3.3 Querier Role and Election

The IGMP querier is the device responsible for periodically sending IGMP general
queries to 224.0.0.1 (all hosts). These queries prompt all multicast receivers
to respond with membership reports, which the switch intercepts to maintain its
snooping table.

Only one querier is active per VLAN at a time. If multiple devices are sending
queries, an election occurs based on the lowest source IP address winning. This
is important to understand because a misconfigured host or an unexpected device
sending queries can win the election and become the de facto querier, displacing
the switch.

Querier election rules:

```
Lowest source IP address wins the election.

0.0.0.0  <  any real IP address

A switch configured with ip igmp snooping querier but no source address
specified will query from 0.0.0.0 and will lose to any host with a real IP.
```

### 3.4 Querier Source Address Selection

The querier source address should be a real, stable IP address associated with
the switch and reachable within the management plane. The recommended source is
an existing SVI that is active on the switch — not a loopback address and not
0.0.0.0.

Rationale for not using a loopback address:

- A loopback is not associated with any VLAN
- Hosts receiving queries from a loopback source have no Layer 2 path back to
  that address since there is no SVI bridging the loopback into the VLAN
- Some multicast-aware stacks validate querier reachability and may behave
  unexpectedly when the querier source is unreachable at L2
- On switches without ip multicast-routing, loopback-sourced queriers may not
  be supported consistently

Recommended approach — use an existing management SVI as the source:

```
ip igmp snooping querier
ip igmp snooping vlan 2601 querier address 10.32.204.254
```

This uses a real, stable address without requiring new SVIs on data VLANs.

### 3.5 Theoretical Scenarios

The following scenarios describe what happens under different querier conditions.
These are provided to aid understanding and troubleshooting.

**Scenario A — No querier anywhere, IGMP snooping enabled**

```
Result: Switch floods multicast to all ports in the VLAN.

Hosts may send unsolicited IGMP reports when joining groups. Snooping will
catch these initial joins and briefly populate the table. When memberships
time out and no queries arrive to refresh them, the table ages out and the
switch falls back to flooding.

Multicast is delivered but to every port in the VLAN, not just subscribers.
For a VLAN with few ports and controlled applications this may be acceptable.
```

**Scenario B — A host acts as querier**

```
Result: Multicast works correctly if the host sends compliant IGMP queries.

Some multicast applications and Linux stacks with smcroute or pimd running
will send IGMP queries if they detect no querier. The switch snoops those
host-generated queries exactly as it would switch-generated ones. The host
with the lowest IP address in the VLAN wins the querier election.

This is not a reliable production design but explains why multicast may
appear to work even without an explicit querier configured on the switch.
```

**Scenario C — Switch querier sourcing from 0.0.0.0**

```
Result: Works correctly only if no host on the VLAN has a lower IP address
and is also sending queries (which no real IP can be lower than 0.0.0.0).

In practice 0.0.0.0 always wins the election since it is numerically lower
than any valid IP. However using 0.0.0.0 is technically non-compliant and
some hosts may reject or ignore queries from this source. Specifying a real
SVI address is always preferred.
```

**Scenario D — ip multicast-routing enabled, no PIM on L2 VLAN SVIs**

```
Result: Unpredictable. Multicast frames for those VLANs may be dropped.

When ip multicast-routing is enabled globally, IOS-XE hands multicast
forwarding decisions to the PIM subsystem even for VLANs where only L2
forwarding is needed. If no SVI exists for a VLAN, PIM has no interface
to process membership for that group. The result is that IGMP snooping
table entries may not be populated correctly and multicast may be silently
dropped rather than flooded.

Fix: Add an IGMP snooping querier per affected VLAN sourced from an
existing SVI. This keeps ip multicast-routing in place and gives IGMP
snooping the information it needs to operate independently of PIM for
those VLANs.
```

---

## 4. Layer 2 Only Switch — Access Layer (SWITCH02 Style)

### 4.1 Characteristics

A pure access layer switch in this design has the following properties:

- No `ip routing` configured
- No `ip multicast-routing` configured
- No SVIs defined on data VLANs (2601–2624 and others)
- One management SVI (e.g. Vlan3224) for in-band access
- Access ports connecting physical client devices
- One trunk uplink to the aggregation switch

Because ip multicast-routing is absent, IGMP snooping operates in its native
standalone mode. This is the simpler and more predictable of the two switch
roles for multicast configuration.

### 4.2 Recommended Configuration

Enable IGMP snooping querier globally and per VLAN, sourced from the management
SVI. No PIM configuration is needed or appropriate on this switch.

Global querier enable:

```
ip igmp snooping querier
```

Per-VLAN querier configuration (repeat for each active data VLAN):

```
ip igmp snooping vlan 2601 querier address 10.32.204.253
ip igmp snooping vlan 2602 querier address 10.32.204.253
ip igmp snooping vlan 2603 querier address 10.32.204.253
ip igmp snooping vlan 2604 querier address 10.32.204.253
ip igmp snooping vlan 2605 querier address 10.32.204.253
ip igmp snooping vlan 2606 querier address 10.32.204.253
ip igmp snooping vlan 2607 querier address 10.32.204.253
ip igmp snooping vlan 2608 querier address 10.32.204.253
ip igmp snooping vlan 2609 querier address 10.32.204.253
ip igmp snooping vlan 2610 querier address 10.32.204.253
ip igmp snooping vlan 2611 querier address 10.32.204.253
ip igmp snooping vlan 2612 querier address 10.32.204.253
ip igmp snooping vlan 2613 querier address 10.32.204.253
ip igmp snooping vlan 2614 querier address 10.32.204.253
ip igmp snooping vlan 2615 querier address 10.32.204.253
ip igmp snooping vlan 2616 querier address 10.32.204.253
ip igmp snooping vlan 2617 querier address 10.32.204.253
ip igmp snooping vlan 2618 querier address 10.32.204.253
ip igmp snooping vlan 2619 querier address 10.32.204.253
ip igmp snooping vlan 2620 querier address 10.32.204.253
ip igmp snooping vlan 2621 querier address 10.32.204.253
ip igmp snooping vlan 2622 querier address 10.32.204.253
ip igmp snooping vlan 2623 querier address 10.32.204.253
ip igmp snooping vlan 2624 querier address 10.32.204.253
```

Management SVI (already present, shown for reference):

```
interface Vlan3224
 description ADMIN
 ip address 10.32.204.253 255.255.255.0
```

### 4.3 Verification Commands

Verify IGMP snooping is enabled globally:

```
show ip igmp snooping
```

Verify querier status per VLAN:

```
show ip igmp snooping querier detail
```

Verify group membership table for a specific VLAN:

```
show ip igmp snooping groups vlan 2601
```

Verify multicast is being forwarded to the correct ports:

```
show mac address-table multicast vlan 2601
```

---

## 5. Aggregation Switch — Mixed L2/L3 (SWITCH01 Style)

### 5.1 Characteristics

The aggregation switch in this design has the following properties:

- `ip routing` enabled
- `ip multicast-routing` enabled
- SVIs defined for management and server VLANs (Vlan31, Vlan3220, Vlan3221,
  Vlan3224) but not for data VLANs (2601–2624 and others)
- LACP bond trunk uplinks to Proxmox servers (Po1–Po4)
- Trunk downlink to access layer switch
- Trunk uplink to core switches

### 5.2 Impact of ip multicast-routing on L2 VLANs

When `ip multicast-routing` is enabled globally on IOS-XE, the switch hands
multicast forwarding decisions to the PIM subsystem. For VLANs that have an SVI
with PIM configured, this works as expected. For VLANs that have no SVI and no
PIM interface, the behavior changes in a way that is not immediately obvious.

The issue:

```
ip multicast-routing is enabled globally
  ↓
PIM subsystem takes over multicast forwarding decisions
  ↓
VLAN 2601 has no SVI, therefore no PIM interface
  ↓
PIM has no membership state for VLAN 2601 groups
  ↓
Multicast frames for VLAN 2601 may be dropped silently
  ↓
IGMP snooping table entries may not be populated correctly
```

This is distinct from the access layer switch case where IGMP snooping operates
standalone without interference from PIM.

Two remediation options exist:

**Option A — Add IGMP snooping querier per L2 VLAN (Recommended)**

Keeps ip multicast-routing in place. Surgical change with low risk. The querier
gives IGMP snooping the information it needs to operate independently for L2
VLANs without requiring PIM on those VLANs.

**Option B — Remove ip multicast-routing**

Returns IGMP snooping to standalone mode. Appropriate if no routed multicast is
needed anywhere on the switch. Higher risk if other parts of the environment
depend on ip multicast-routing being present.

### 5.3 Recommended Configuration

Using Option A. Sourced from the existing Vlan3224 SVI (10.32.204.254).

Global querier enable:

```
ip igmp snooping querier
```

Per-VLAN querier configuration for all L2 data VLANs:

```
ip igmp snooping vlan 100 querier address 10.32.204.254
ip igmp snooping vlan 101 querier address 10.32.204.254
ip igmp snooping vlan 102 querier address 10.32.204.254
ip igmp snooping vlan 110 querier address 10.32.204.254
ip igmp snooping vlan 111 querier address 10.32.204.254
ip igmp snooping vlan 470 querier address 10.32.204.254
ip igmp snooping vlan 472 querier address 10.32.204.254
ip igmp snooping vlan 1000 querier address 10.32.204.254
ip igmp snooping vlan 2000 querier address 10.32.204.254
ip igmp snooping vlan 2601 querier address 10.32.204.254
ip igmp snooping vlan 2602 querier address 10.32.204.254
ip igmp snooping vlan 2603 querier address 10.32.204.254
ip igmp snooping vlan 2604 querier address 10.32.204.254
ip igmp snooping vlan 2605 querier address 10.32.204.254
ip igmp snooping vlan 2606 querier address 10.32.204.254
ip igmp snooping vlan 2607 querier address 10.32.204.254
ip igmp snooping vlan 2608 querier address 10.32.204.254
ip igmp snooping vlan 2609 querier address 10.32.204.254
ip igmp snooping vlan 2610 querier address 10.32.204.254
ip igmp snooping vlan 2611 querier address 10.32.204.254
ip igmp snooping vlan 2612 querier address 10.32.204.254
ip igmp snooping vlan 2613 querier address 10.32.204.254
ip igmp snooping vlan 2614 querier address 10.32.204.254
ip igmp snooping vlan 2615 querier address 10.32.204.254
ip igmp snooping vlan 2616 querier address 10.32.204.254
ip igmp snooping vlan 2617 querier address 10.32.204.254
ip igmp snooping vlan 2618 querier address 10.32.204.254
ip igmp snooping vlan 2619 querier address 10.32.204.254
ip igmp snooping vlan 2620 querier address 10.32.204.254
ip igmp snooping vlan 2621 querier address 10.32.204.254
ip igmp snooping vlan 2622 querier address 10.32.204.254
ip igmp snooping vlan 2623 querier address 10.32.204.254
ip igmp snooping vlan 2624 querier address 10.32.204.254
```

Existing Vlan3224 SVI (already present, shown for reference):

```
interface Vlan3224
 description ADMIN
 ip address 10.32.204.254 255.255.255.0
```

### 5.4 Verification Commands

Verify IGMP snooping global status:

```
show ip igmp snooping
```

Verify querier per VLAN:

```
show ip igmp snooping querier detail
```

Verify group membership:

```
show ip igmp snooping groups vlan 2601
```

Verify multicast forwarding table:

```
show ip mroute
```

Verify PIM neighbors (should only appear on SVIs where PIM is configured):

```
show ip pim neighbor
```

Verify IGMP groups on a specific SVI:

```
show ip igmp groups
```

---

## 6. Spanning Tree Interaction with Multicast

### 6.1 TCN-Triggered Multicast Table Flushing

When a Topology Change Notification (TCN) occurs in a spanning tree domain, the
switch flushes its MAC address table to prevent stale forwarding entries. On
IOS-XE, this flush also clears the IGMP snooping group membership table for the
affected VLANs.

The sequence of events:

```
Link flap or topology change occurs
  ↓
STP generates a TCN
  ↓
Switch flushes MAC address table for affected VLANs
  ↓
IGMP snooping group membership table is also flushed
  ↓
Switch falls back to flooding multicast to all ports
  ↓
Hosts must re-send IGMP joins to rebuild membership state
  ↓
Multicast delivery is temporarily disrupted until membership is restored
```

The duration of disruption depends on how quickly hosts re-join their groups.
Applications that rejoin immediately upon detecting stream loss recover quickly.
Applications that rely on periodic IGMP reports may take up to the report
interval (default 125 seconds for IGMPv2/v3) to recover.

Mitigation: Ensure rapid-PVST is configured and all access ports have PortFast
enabled so TCNs are not generated by end device link events. See section 6.2.

Verify TCN events:

```
show spanning-tree vlan 2601 detail | include topology
```

### 6.2 PortFast Interaction

PortFast is a spanning tree feature that causes an access port to transition
directly to the forwarding state when a link comes up, bypassing the listening
and learning states. This has a direct and important relationship with multicast.

Without PortFast on an access port:

```
Device connects to port
  ↓
Port enters listening state (15 seconds)
  ↓
Port enters learning state (15 seconds)
  ↓
Port enters forwarding state
  ↓
Total delay: 30 seconds before traffic flows
  ↓
During this time the switch generates TCNs, flushing multicast tables
```

With PortFast on an access port:

```
Device connects to port
  ↓
Port immediately enters forwarding state
  ↓
No TCN is generated
  ↓
Multicast snooping tables are not flushed
```

PortFast should be enabled on all access ports connected to end devices
(physical clients, servers, VM uplinks that are access ports). It must not be
enabled on trunk ports between switches.

Configuration per access port:

```
interface GigabitEthernet1/0/1
 spanning-tree portfast
```

Global default for all access ports (use with caution on aggregation switches):

```
spanning-tree portfast default
```

Note: On the access layer switch (SWITCH02 style), enabling PortFast globally
is appropriate since all non-trunk ports connect to end devices. On the
aggregation switch (SWITCH01 style), configure PortFast explicitly per port
rather than globally to avoid accidentally enabling it on trunk interfaces.

### 6.3 BPDU Guard Interaction

BPDU Guard is a security feature that disables a PortFast-enabled port if it
receives a BPDU. Its relationship with multicast is indirect but important.

If a PortFast port receives a BPDU (from a rogue switch or a misconfigured VM
sending BPDUs), BPDU Guard error-disables the port. The port going down and
then recovering (after errdisable recovery) generates a TCN, which flushes
multicast tables as described in section 6.1.

BPDU Guard should always be paired with PortFast on end device ports:

```
interface GigabitEthernet1/0/1
 spanning-tree portfast
 spanning-tree bpduguard enable
```

Ensure errdisable recovery is configured so that a transient BPDU event does
not permanently disable the port:

```
errdisable recovery cause bpduguard
errdisable recovery interval 60
```

Verify error-disabled ports:

```
show interfaces status err-disabled
```

Verify BPDU Guard status:

```
show spanning-tree summary
```

### 6.4 Recommended Spanning Tree Settings for Multicast Ports

The following configuration represents best practice for access ports carrying
multicast traffic on Catalyst 9200/9300:

```
interface GigabitEthernet1/0/1
 description client-device
 switchport access vlan 2601
 switchport mode access
 spanning-tree portfast
 spanning-tree bpduguard enable
 spanning-tree guard root
```

For trunk ports between switches, never enable PortFast. Use point-to-point
link type to ensure rapid transition:

```
interface GigabitEthernet1/0/24
 description TRUNK-TO-SWITCH01
 switchport mode trunk
 spanning-tree link-type point-to-point
```

---

## 7. RSPAN Interaction with Multicast

### 7.1 General Risk

RSPAN (Remote Switched Port Analyzer) works by copying frames from a source
port or VLAN and flooding them into a designated RSPAN VLAN. The switch then
floods that RSPAN VLAN out all trunk ports that carry it, regardless of whether
there is a destination monitoring port downstream.

This flooding behavior creates two specific risks for multicast:

**Risk 1 — RSPAN traffic masquerades as multicast**

RSPAN copies frames verbatim including their destination MAC addresses. If the
mirrored traffic includes multicast frames (which it almost always will given
that IGMP, PVST+, and application multicast all use multicast MAC addresses),
those copied frames enter the RSPAN VLAN and are flooded everywhere the RSPAN
VLAN is carried. This can cause multicast frames from production VLANs to appear
unexpectedly on monitoring endpoints in other parts of the network.

**Risk 2 — RSPAN VLAN flooding interferes with IGMP snooping**

Because RSPAN floods frames rather than forwarding them based on MAC learning,
the IGMP snooping process on intermediate switches may see IGMP report frames
in the RSPAN VLAN arriving from unexpected directions. If the RSPAN VLAN is
not correctly marked as remote-span on all intermediate switches, the switch
may attempt to process these IGMP frames as real membership reports and
incorrectly populate its snooping table.

The critical requirement: every switch that carries the RSPAN VLAN in its
trunk allowed list must have the VLAN defined as remote-span in its VLAN
database. Without this, the switch treats RSPAN traffic as normal Layer 2
traffic and multicast snooping state can be corrupted.

Required on every switch carrying the RSPAN VLAN:

```
vlan 50
 name RSPAN
 remote-span
```

### 7.2 Worked Example — VLAN 50 and 239.x.x.x

In this environment RSPAN VLAN 50 is configured as follows:

```
Source:      SWITCH02 Gi1/0/16 (access port, VLAN 2616)
Destination: RSPAN VLAN 50
Path:        SWITCH02 → SWITCH01 → PVE04 bond999 → vmbr999 → Debian VM (tag 50)
```

The RSPAN session on SWITCH02:

```
monitor session 1 source interface Gi1/0/16
monitor session 1 destination remote vlan 50
```

The Debian VM on PVE04 with NIC tagged to VLAN 50 receives the mirrored stream.

Multicast interaction in this scenario:

```
Physical client on Gi1/0/16 sends multicast to 239.x.x.x
  ↓
SWITCH02 mirrors the frame into RSPAN VLAN 50
  ↓
The mirrored frame includes the original 239.x.x.x destination
  ↓
Frame is flooded across trunk to SWITCH01 in VLAN 50
  ↓
SWITCH01 floods VLAN 50 out Po4 toward PVE04
  ↓
Debian VM receives the mirrored multicast frame tagged as VLAN 50
  ↓
Wireshark on the VM sees 239.x.x.x traffic — this is expected and correct
```

What you observe in Wireshark on the Debian VM is the full unmodified frame
including PVST+ BPDUs, ARP broadcasts, and multicast application traffic. This
is correct behavior — the RSPAN session delivers everything that crosses the
source port.

Important: the 239.x.x.x traffic appearing in the RSPAN capture is a copy of
the production multicast stream. It does not represent the VM joining that
multicast group. The VM is a passive receiver of the mirror, not a multicast
subscriber in VLAN 2616.

### 7.3 Mitigation

To prevent RSPAN from interfering with multicast outside its intended scope:

1. Ensure all switches carrying VLAN 50 have `vlan 50 remote-span` defined.
   Missing this on any intermediate switch causes RSPAN frames to be processed
   as normal L2 traffic and corrupts multicast snooping state.

2. Limit the RSPAN VLAN to only the trunk segments that need it. If CORE1234
   and CORE5678 have no RSPAN destination, remove VLAN 50 from the trunk
   allowed list on SWITCH01's uplink to CORE1234:

   ```
   interface GigabitEthernet1/0/47
    switchport trunk allowed vlan remove 50
   ```

3. Do not place production VMs or servers on the RSPAN VLAN. A capture VM
   receiving mirrored traffic is the intended and correct use. A production
   VM on the RSPAN VLAN will receive flooded mirror traffic and may behave
   unexpectedly.

4. Monitor RSPAN VLAN bandwidth utilization. On a busy source port, the
   mirror copy doubles the traffic on the RSPAN VLAN across all trunk segments
   that carry it. This can impact trunk utilization between switches.

---

## 8. Troubleshooting

### 8.1 Multicast Not Reaching Receivers

Symptom: Sender is transmitting, receiver is not receiving anything.

Step 1 — Verify IGMP snooping is enabled:

```
show ip igmp snooping
```

Step 2 — Verify the receiver port appears in the group membership table:

```
show ip igmp snooping groups vlan 2601
```

If the receiver port is not listed, the switch has not seen an IGMP join from
that port. Check that the receiver application has joined the group and that
the host OS is sending IGMP reports.

Step 3 — Verify a querier is active:

```
show ip igmp snooping querier detail
```

If no querier is shown, IGMP snooping has no queries to work from and will
not maintain membership state. Add a querier per section 4.2 or 5.3.

Step 4 — Verify multicast is not being blocked by ip multicast-routing:

```
show ip mroute
```

If the group appears here with no outgoing interfaces, PIM is not forwarding
it. This indicates the Scenario D condition from section 3.5. Add per-VLAN
IGMP snooping querier configuration as in section 5.3.

Step 5 — Capture at the port level:

```
monitor session 1 source interface Gi1/0/1 rx
monitor session 1 destination interface Gi1/0/2
```

Capture on the destination port using a device running tcpdump or Wireshark
to verify whether multicast frames are physically arriving at the switch port.

### 8.2 Multicast Flooding to All Ports

Symptom: Multicast traffic is being delivered to all ports in the VLAN, not
just subscribed receivers. Causes unnecessary load on unsubscribed devices.

Step 1 — Verify IGMP snooping is enabled for the specific VLAN:

```
show ip igmp snooping vlan 2601
```

If snooping shows disabled for that VLAN, enable it:

```
ip igmp snooping vlan 2601
```

Step 2 — Verify a querier is present and active:

```
show ip igmp snooping querier vlan 2601 detail
```

Step 3 — Verify the multicast group is not in the well-known range. Groups in
224.0.0.0/24 are link-local and are always flooded by design. This is expected
behavior, not a misconfiguration. Groups in 239.x.x.x should be snooped
correctly once a querier is active.

Step 4 — Check for TCN events causing table flushes:

```
show spanning-tree vlan 2601 detail | include topology
```

Repeated TCNs will repeatedly flush the snooping table causing repeated
flooding events. Resolve the underlying topology instability and ensure
PortFast is configured on all access ports.

### 8.3 Querier Election Conflicts

Symptom: Multicast works intermittently. The show ip igmp snooping querier
detail output shows a querier IP that is not the switch.

This means a host on the VLAN is winning the querier election. If the winning
host IP is lower than the switch querier source, the host becomes the querier.

Step 1 — Identify the winning querier:

```
show ip igmp snooping querier vlan 2601 detail
```

Note the querier IP address and identify which device it belongs to.

Step 2 — Determine whether the host querier is intentional. If not, investigate
why the host is sending IGMP queries. Linux hosts running smcroute or pimd may
send queries by default. Windows hosts generally do not send queries unless a
specific multicast application is configured to do so.

Step 3 — If the host querier is reliable and correct, this can be left in place.
If it is unreliable, either configure the switch querier with a lower IP than
the host, or disable the querier function on the host application.

### 8.4 Multicast Disrupted After Topology Change

Symptom: Multicast stops working briefly after a link flap, switch reload, or
spanning tree reconvergence. Recovery is automatic but takes 30–120 seconds.

This is the TCN flush behavior described in section 6.1.

Step 1 — Identify which port caused the TCN:

```
show spanning-tree vlan 2601 detail | include from
```

Step 2 — Verify PortFast is configured on all access ports for the affected VLAN:

```
show spanning-tree interface GigabitEthernet1/0/1 portfast
```

Step 3 — If PortFast is already configured and TCNs are still occurring, the
source of the TCN is likely a trunk port. Check trunk port stability:

```
show interfaces GigabitEthernet1/0/24 | include line protocol
```

Step 4 — To reduce recovery time after a TCN flush, ensure hosts and VMs are
configured to send immediate IGMP joins when their multicast application starts
or detects stream loss. This is application-specific but reduces the recovery
window from the full report interval to near-instantaneous.

---

## 9. Glossary

| Term              | Definition                                                                 |
|-------------------|----------------------------------------------------------------------------|
| BPDU              | Bridge Protocol Data Unit. Control frame used by spanning tree.            |
| BPDU Guard        | Disables a PortFast port that receives a BPDU.                             |
| IGMP              | Internet Group Management Protocol. Used by hosts to join multicast groups.|
| IGMP Snooping     | Switch feature that intercepts IGMP traffic to build multicast port maps.  |
| IGMPv2            | IGMP version 2. Adds leave group message for faster multicast leave.       |
| IGMPv3            | IGMP version 3. Adds source-specific multicast support.                    |
| Intra-VLAN        | Traffic that stays within a single VLAN and does not require routing.      |
| ip multicast-routing | IOS-XE global command that enables PIM-based multicast routing.         |
| Multicast Group   | An IP address in the 224.0.0.0/4 range representing a set of receivers.   |
| PIM               | Protocol Independent Multicast. Routing protocol for multicast streams.    |
| PortFast          | STP feature that skips listening/learning on access ports.                 |
| Querier           | The device responsible for sending periodic IGMP general queries.          |
| Querier Election  | Process by which the lowest IP address device becomes the active querier.  |
| Rapid-PVST        | Rapid Per-VLAN Spanning Tree. IEEE 802.1w with per-VLAN instances.        |
| RP                | Rendezvous Point. Central meeting point for PIM sparse mode multicast.     |
| RSPAN             | Remote Switched Port Analyzer. Mirrors traffic across a network to a VLAN. |
| SVI               | Switched Virtual Interface. A Layer 3 interface defined for a VLAN.        |
| TCN               | Topology Change Notification. STP message indicating a topology change.    |
| Trunk             | Switch port carrying multiple VLANs using 802.1Q tagging.                  |
| VLAN              | Virtual Local Area Network. Logical network segment within a switch.       |
