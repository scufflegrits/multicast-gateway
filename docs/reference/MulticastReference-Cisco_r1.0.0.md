# Multicast Reference Guide — Cisco Catalyst 9200 / 9300

**Coverage: IPv4 multicast only.** IPv6/MLD configuration and validation are
outside this guide. mcgw itself retains its separate IPv4/IPv6 design scope.

| Field          | Detail                          |
|----------------|---------------------------------|
| Version        | 1.0.0                           |
| Last Updated   | 20261017                        |
| Author         | sysadmin                        |
| Filename       | MulticastReference-Cisco_r1.0.0.md |

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

| Version | Date     | Author    | Change Summary  |
|---------|----------|-----------|-----------------|
| Review | 20261017 | scufflegrits | IPv4-only scope; technical corrections, clickable navigation, acronym and verification-source appendices; filename/version retained |
| 1.0.0   | 20250517 | sysadmin  | Initial release |

---

## Table of Contents

- [Scope and command use](#scope-and-command-use)
- [Revision History](#revision-history)
- [1. Overview](#1-overview)
- [2. Multicast Fundamentals](#2-multicast-fundamentals)
  - [2.1 How IP Multicast Works](#21-how-ip-multicast-works)
  - [2.2 IGMP Versions](#22-igmp-versions)
  - [2.3 Multicast Address Ranges](#23-multicast-address-ranges)
- [3. IGMP Snooping](#3-igmp-snooping)
  - [3.1 What IGMP Snooping Does](#31-what-igmp-snooping-does)
  - [3.2 Default Behavior on IOS-XE](#32-default-behavior-on-ios-xe)
  - [3.3 Querier Role and Election](#33-querier-role-and-election)
  - [3.4 Querier Source Address Selection](#34-querier-source-address-selection)
  - [3.5 Theoretical Scenarios](#35-theoretical-scenarios)
- [4. Layer 2 Only Switch — Access Layer (SWITCH02 Style)](#4-layer-2-only-switch--access-layer-switch02-style)
  - [4.1 Characteristics](#41-characteristics)
  - [4.2 Recommended Configuration](#42-recommended-configuration)
  - [4.3 Verification Commands](#43-verification-commands)
- [5. Aggregation Switch — Mixed L2/L3 (SWITCH01 Style)](#5-aggregation-switch--mixed-l2l3-switch01-style)
  - [5.1 Characteristics](#51-characteristics)
  - [5.2 Impact of ip multicast-routing on L2 VLANs](#52-impact-of-ip-multicast-routing-on-l2-vlans)
  - [5.3 Recommended Configuration](#53-recommended-configuration)
  - [5.4 Verification Commands](#54-verification-commands)
- [6. Spanning Tree Interaction with Multicast](#6-spanning-tree-interaction-with-multicast)
  - [6.1 TCN-Triggered Multicast Table Flushing](#61-tcn-triggered-multicast-table-flushing)
  - [6.2 PortFast Interaction](#62-portfast-interaction)
  - [6.3 BPDU Guard Interaction](#63-bpdu-guard-interaction)
  - [6.4 Recommended Spanning Tree Settings for Multicast Ports](#64-recommended-spanning-tree-settings-for-multicast-ports)
- [7. RSPAN Interaction with Multicast](#7-rspan-interaction-with-multicast)
  - [7.1 General Risk](#71-general-risk)
  - [7.2 Worked Example — VLAN 50 and 239.x.x.x](#72-worked-example--vlan-50-and-239xxx)
  - [7.3 Mitigation](#73-mitigation)
- [8. Troubleshooting](#8-troubleshooting)
  - [8.1 Multicast Not Reaching Receivers](#81-multicast-not-reaching-receivers)
  - [8.2 Multicast Flooding to All Ports](#82-multicast-flooding-to-all-ports)
  - [8.3 Querier Election Conflicts](#83-querier-election-conflicts)
  - [8.4 Multicast Disrupted After Topology Change](#84-multicast-disrupted-after-topology-change)
- [9. Glossary](#9-glossary)
- [Appendix A — Acronyms and meanings](#appendix-a--acronyms-and-meanings)
- [Appendix B — Verification sources](#appendix-b--verification-sources)
  - [Qualification still required](#qualification-still-required)

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

Inspect the SVI IGMP version and snooping-querier version separately.
IGMPv3-capable host/report support does not establish IGMPv3 query generation.

### 2.3 Multicast Address Ranges

| Range                     | Purpose                                      |
|---------------------------|----------------------------------------------|
| 224.0.0.0/24              | Link-local, not forwarded by routers         |
| 224.0.1.0 – 238.255.255.255 | Includes multiple allocation categories, including 232/8 SSM; consult the registry |
| 239.0.0.0/8               | Administratively scoped, private use         |
| 240.0.0.0/4               | Reserved                                     |

For intra-VLAN multicast in a private lab or enterprise environment, the
239.0.0.0/8 range is a common ASM choice, subject to the organization's group allocation. These addresses are analogous to RFC
1918 private unicast addresses — they require administratively enforced scope boundaries; the address alone
does not create a security or routing boundary.

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

IGMP snooping is normally enabled on these Catalyst platforms; inspect effective
global and per-VLAN state. Without a working querier, initial unsolicited reports
can create state that later ages out. Subsequent unknown-multicast forwarding
is platform/configuration-dependent; do not assume guaranteed flooding or loss.

```
show ip igmp snooping
show ip igmp snooping vlan 2601
show ip igmp snooping groups vlan 2601
```

Snooping and querier generation are different features; record each separately.

### 3.3 Querier Role and Election

A querier periodically solicits host memberships. Normal IGMPv2/v3 router
querier election favors the lower valid interface address. A switch's snooping
querier also has platform-specific activation/nonquerier rules; it is not
interchangeable with a PIM-enabled SVI's IGMP function.

Do not claim a `0.0.0.0` source always wins or loses. Inspect operational state
and captured queries. Cisco documents source fallback and no-query behavior
when no address is available (C1).

### 3.4 Querier Source Address Selection

Select a stable address under the deployed platform's documented rules. The
management-SVI addresses below are lab examples, not universal requirements.
IGMP replies are multicast; an L2 unicast path back to the query source is not
by itself the membership criterion.

Example global syntax; confirm release-specific CLI before applying:

```
ip igmp snooping querier
ip igmp snooping querier address 10.32.204.254
```

Per-VLAN overrides, operational source selection, and interaction with a routed
querier must be verified for the exact image. Use `show ip igmp snooping querier`
and a wire capture; configuring an address alone does not prove querying.

### 3.5 Theoretical Scenarios

| Situation | Investigate / expected boundary |
|---|---|
| No querier | Initial reports may be learned and later age out; inspect unknown-group policy |
| Host runs a routing/querier service | May introduce a querier; a plain multicast join or smcroute membership entry alone does not imply query generation |
| Zero or unexpected query source | Inspect source selection and operational state; no numeric-address shortcut |
| Global multicast routing enabled | Inspect L2 snooping and per-VLAN routed state separately; no general rule that PIM takes over unrelated L2 forwarding |
| Source-specific feed | Verify actual membership protocol capabilities, source lists and routed source/group setup |

A switch that recognizes IGMPv3 reports may still generate only IGMPv1/v2
snooping queries. C1 documents that distinction for Catalyst 9300 17.15.x.
Verify target images before claiming a source-specific deployment is supported.

## 4. Layer 2 Only Switch — Access Layer (SWITCH02 Style)

### 4.1 Characteristics

A pure access layer switch in this design has the following properties:

- No `ip routing` configured
- No `ip multicast-routing` configured
- No SVIs defined on data VLANs (2601–2624 and others)
- One management SVI (e.g. Vlan3224) for in-band access
- Access ports connecting physical client devices
- One trunk uplink to the aggregation switch

This role needs L2 distribution; routed multicast state is not a prerequisite.
Verify actual snooping and query ownership separately.

### 4.2 Recommended Configuration

For an L2-only VLAN, confirm whether an upstream querier already exists. Add a
snooping querier only where the network design requires one; no PIM is needed
merely to switch intra-VLAN traffic.

Lab example (global source affects the switch's querier policy):

```
ip igmp snooping querier
ip igmp snooping querier address 10.32.204.253
```

Verify VLAN 2601 operational state before repeating changes elsewhere. Preserve
existing management addressing; do not create data SVIs or broad per-VLAN
configuration simply to copy this example. Release-specific overrides need
on-device syntax/behavior validation.

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

Multicast routing controls routed forwarding; IGMP snooping controls L2 port
distribution. Global routing enablement alone does not establish that unrelated
L2 VLANs require PIM or lose multicast traffic.

Inspect per-VLAN memberships, router ports, queries and actual data. Attribute
an unexpected interaction to a specific image/configuration or documented
defect before changing global routing. Do not remove `ip multicast-routing`
as a generic fix; other VLANs may depend on it.

### 5.3 Recommended Configuration

Determine the query owner per VLAN. A PIM-enabled SVI's IGMP querying and a
standalone snooping querier have different roles. Cisco documents the snooping
querier becoming inactive when PIM is enabled on the corresponding SVI (C1).

For L2-only VLANs needing this switch to query, use the release-supported
snooping-querier configuration, then verify operational state. Example:

```
ip igmp snooping querier
ip igmp snooping querier address 10.32.204.254
```

Retain routed multicast on VLANs requiring it. Avoid bulk configuration across
all lab VLAN IDs before verifying query ownership, address selection and traffic.

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

A spanning-tree topology change can alter multicast distribution and temporary
flooding. Do not equate MAC-table changes with universal IGMP-table deletion or
assume every application must leave/rejoin.

For Catalyst 9300, C1 documents different STP edge/non-edge flooding behavior
from IOS XE 17.11.1. Test the deployed release and configured TCN flood/query
settings instead of promising a fixed recovery time.

```
show spanning-tree vlan 2601 detail | include topology
show ip igmp snooping vlan 2601
show ip igmp snooping groups vlan 2601
```

Compare before/after membership and captures. A 125-second query interval is
not a universal outage duration.

### 6.2 PortFast Interaction

PortFast/edge configuration is for ports connected only to end systems. Apply
it according to actual topology, not because the traffic happens to be multicast.
Do not enable edge behavior on a switch-to-switch connection. A host trunk may
need platform-specific edge-trunk treatment after validating that it cannot
form a bridge loop.

Example end-device access port:

```
interface GigabitEthernet1/0/1
 spanning-tree portfast
```

Convergence depends on STP mode, port role and policy; do not assume every
non-PortFast port incurs a fixed 30-second delay.

### 6.3 BPDU Guard Interaction

BPDU Guard can error-disable an edge port receiving BPDUs. Diagnose the source
and topology before restoring it. Automatic error-disable recovery is an
operator policy, not a mandatory multicast setting; repeated recovery can
reintroduce the same fault.

Example for a verified end-device edge port:

```
interface GigabitEthernet1/0/1
 spanning-tree portfast
 spanning-tree bpduguard enable
```

Inspect state before deciding on recovery:

```
show interfaces status err-disabled
show spanning-tree summary
```

Do not infer a specific multicast-table flush from every guard event.

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

RSPAN copies mirrored frames with their original destination MAC addresses,
but carries them in the RSPAN VLAN in place of their original VLAN identity.
Not every frame is mirrored: certain Layer 2 control protocols (for example
STP BPDUs, CDP, VTP, DTP and PAgP) are excluded on the documented Catalyst 9300
release (C4). Mirrored multicast frames (IGMP and application multicast use
multicast MAC addresses) enter the RSPAN VLAN and are flooded everywhere the
RSPAN VLAN is carried. This can cause multicast frames from production VLANs to appear
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
database. Without correct provisioning, monitoring traffic may follow unintended L2
behavior; inspect actual membership/forwarding before attributing a defect.

Required on every switch carrying the RSPAN VLAN:

```
vlan 50
 name RSPAN
 remote-span
```

### 7.2 Worked Example — VLAN 50 and 239.x.x.x

The documented RSPAN construction has three parts (C4): a source session that
copies the source port into the RSPAN VLAN, the RSPAN VLAN as transport, and a
destination session that copies the RSPAN VLAN to a physical destination port
where the capture host is attached:

```
Source:      SWITCH02 Gi1/0/16 (access port, VLAN 2616)
Transport:   RSPAN VLAN 50 (SWITCH02 → SWITCH01 trunk)
Destination: SWITCH01 destination port (example Gi1/0/24) → capture host NIC
```

The RSPAN source session on SWITCH02:

```
monitor session 1 source interface Gi1/0/16
monitor session 1 destination remote vlan 50
```

The RSPAN destination session on SWITCH01 (example port; select an unused one):

```
monitor session 2 source remote vlan 50
monitor session 2 destination interface Gi1/0/24
```

The capture host can be a physical machine on Gi1/0/24, or a capture VM given
that port through a dedicated PVE04 NIC.

**Unqualified lab extension: VM on the transport VLAN.** Carrying VLAN 50 on
Po4 to PVE04 and attaching a Debian VM with a NIC tagged 50 to vmbr999 consumes
the transport VLAN directly, without a destination session. This is not the
documented construction and must be validated before relying on it. Points to
test include: whether all expected mirrored frames reach the VM; vmbr999 MAC
learning on VLAN 50 (mirrored source MACs learned on bond999 can cause later
mirrored frames to those MACs to be dropped rather than forwarded to the tap);
bridge multicast snooping on VLAN 50 filtering mirrored multicast; and the
guest NIC's promiscuous capture behavior. The flow below describes this
extension as built in the lab.

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

What you observe in Wireshark is the mirrored traffic the platform supports
(for example ARP broadcasts and multicast application traffic), not a complete
original-wire record. Excluded Layer 2 protocols such as STP BPDUs do not
appear, the original VLAN tag is replaced by the RSPAN VLAN, and replication
limits or oversubscription can drop mirrored copies. Treat absence of a frame
in the capture as inconclusive about the source port.

Important: the 239.x.x.x traffic appearing in the RSPAN capture is a copy of
the production multicast stream. It does not represent the VM joining that
multicast group. The VM is a passive receiver of the mirror, not a multicast
subscriber in VLAN 2616.

### 7.3 Mitigation

To prevent RSPAN from interfering with multicast outside its intended scope:

1. Ensure all switches carrying VLAN 50 have `vlan 50 remote-span` defined.
   An incorrectly provisioned monitoring VLAN can change forwarding behavior;
   verify observed effects rather than asserting inevitable snooping corruption.

2. Limit the RSPAN VLAN to only the trunk segments that need it. If CORE1234
   and CORE5678 have no RSPAN destination, remove VLAN 50 from the trunk
   allowed list on SWITCH01's uplink to CORE1234:

   ```
   interface GigabitEthernet1/0/47
    switchport trunk allowed vlan remove 50
   ```

3. Do not place production VMs or servers on the RSPAN VLAN; they will
   receive flooded mirror traffic and may behave unexpectedly. The supported
   capture point is a destination-session port (7.2). A capture VM attached
   directly to the transport VLAN is the unqualified lab extension described
   in 7.2.

4. Monitor RSPAN VLAN bandwidth utilization. On a busy source port, the
   mirror copy adds traffic on the carried monitoring path; utilization depends
   on selected sources, directions, replication and oversubscription. This can impact trunk utilization between switches.

---

## 8. Troubleshooting

### 8.1 Multicast Not Reaching Receivers

| Inspect | Evidence / next step |
|---|---|
| `show ip igmp snooping vlan 2601` | Effective VLAN policy |
| `show ip igmp snooping groups vlan 2601` | Expected destination port/group; absence needs join/source/VLAN investigation |
| `show ip igmp snooping querier detail` | Actual query owner/source/version; compare wire capture |
| `show ip igmp snooping mrouter vlan 2601` | Expected upstream router ports where applicable |
| `show ip mroute` | Relevant only when the flow crosses a routed boundary; empty state does not diagnose intra-VLAN switching |

Trace source and destination ports and confirm VLAN/trunk policy. Create a
SPAN session only after checking existing monitoring configuration; it changes
switch state and can consume monitoring bandwidth. A capture at one point does
not prove application delivery.

### 8.2 Multicast Flooding to All Ports

Check whether traffic is a known group, an unknown group, router-port traffic,
link-local control multicast or an intentional mirror. Inspect query/membership
state and effective unknown-group/TCN behavior before treating flooding as a fault.

```
show ip igmp snooping vlan 2601
show ip igmp snooping groups vlan 2601
show spanning-tree vlan 2601 detail
```

PortFast is a topology decision for eligible edge ports, not a universal fix for
flooding. Capture a bounded sample and record the release/settings.

### 8.3 Querier Election Conflicts

Inspect operational querier state and captured query source/version on each
VLAN. Identify any unexpected routing/querier service. Do not assume a numeric
comparison involving `0.0.0.0` predicts the outcome. Configure query ownership
through the actual platform's documented rules, then verify convergence.

### 8.4 Multicast Disrupted After Topology Change

Record the STP event, affected VLAN/ports, memberships and query traffic before
and after the change. Check edge/non-edge role and release-specific TCN flooding
behavior. Avoid forcing application rejoins or changing STP globally until the
last confirmed distribution point is known.

```
show spanning-tree vlan 2601 detail
show ip igmp snooping groups vlan 2601
show ip igmp snooping querier detail
```

Test the exact target software in the lab; no universal table-flush/recovery
interval is asserted.

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

## Appendix A — Acronyms and meanings

Literal command/API identifiers, interface names and lab device names are not
acronyms. Product names (such as IOS XE, ESXi and VirtIO) identify platforms;
use the vendor documentation for their release-specific behavior.

| Term | Meaning |
|---|---|
| ARP | Address Resolution Protocol |
| ASM | Any-Source Multicast |
| BPDU | Bridge Protocol Data Unit |
| CLI | Command-Line Interface |
| IGMP | Internet Group Management Protocol |
| IP | Internet Protocol |
| IPv4 | Internet Protocol version 4 |
| IPv6 | Internet Protocol version 6 (outside this guide's configuration coverage) |
| L2 | Layer 2 — link-layer switching |
| L3 | Layer 3 — network-layer routing |
| LACP | Link Aggregation Control Protocol |
| MAC | Media Access Control |
| MLD | Multicast Listener Discovery (outside this guide's configuration coverage) |
| NIC | Network Interface Card |
| PIM | Protocol Independent Multicast |
| PVST | Per-VLAN Spanning Tree |
| RFC | Request for Comments |
| RP | Rendezvous Point |
| RSPAN | Remote Switched Port Analyzer |
| SPAN | Switched Port Analyzer |
| SSM | Source-Specific Multicast |
| STP | Spanning Tree Protocol |
| SVI | Switch Virtual Interface |
| TCN | Topology Change Notification |
| VLAN | Virtual Local Area Network |
| VM | Virtual Machine |
| IEEE | Institute of Electrical and Electronics Engineers |

## Appendix B — Verification sources

Accessed/reviewed 2026-10-17. These primary sources support the corrected
mechanisms, not a claim that every command or platform was tested. Configuration
choices and example topology are project guidance. No hardware/VM lab validation
was performed during this revision. Pin tool versions and verify installed help,
service units, policy and vendor release notes before deployment.

| ID | Primary source | Verification scope |
|---|---|---|
| C1 | [Catalyst 9300 IOS XE 17.15.x multicast configuration guide](https://www.cisco.com/c/en/us/td/docs/switches/lan/catalyst9300/software/release/17-15/configuration_guide/ip_mcast_rtng/b_1715_ip_mcast_rtng_9300_cg.pdf) | Querier role/source/version and TCN behavior; not qualification of every target build |
| C2 | [Catalyst 9300 IOS XE 17.13.x multicast command reference](https://www.cisco.com/c/en/us/td/docs/switches/lan/catalyst9300/software/release/17-13/command_reference/b_1713_9300_cr/ip_multicast_routing.html) | CLI mechanism cross-check; exact 17.15/17.18 image syntax must be inspected |
| C3 | [Catalyst 9300 IOS XE 17.12.x IGMP configuration](https://www.cisco.com/c/en/us/td/docs/switches/lan/catalyst9300/software/release/17-12/configuration_guide/ip_mcast_rtng/b_1712_ip_mcast_rtng_9300_cg/configuring_igmp.html) | Earlier documented querier and topology-change behavior; version-specific context |
| C4 | [Catalyst 9300 IOS XE 17.15.x: Configuring SPAN and RSPAN](https://www.cisco.com/c/en/us/td/docs/switches/lan/catalyst9300/software/release/17-15/configuration_guide/nmgmt/b_1715_nmgmt_9300_cg/configuring_span_and_rspan.html) | Mirrored-traffic limitations (excluded L2 protocols, RSPAN VLAN identity) and the source/transport/destination session construction; other platforms/builds unqualified |
| G1 | [RFC 2365 — Administratively Scoped IP Multicast](https://www.rfc-editor.org/rfc/rfc2365.html) | 239/8 scope requires configured administrative boundaries; it is not inherent authentication or isolation |

### Qualification still required

| Evidence | Status |
|---|---|
| Exact OS/device/software versions and effective policy | Record and test at the site |
| Commands/scripts and complete data path | Not executed during this review |
| Throughput, loss, failover and recovery | Not measured; examples are not guarantees |
| IPv6/MLD | Explicitly outside this guide |
| C8570-G2 / Catalyst 9400 and exact 17.18.4 / 17.15.6 builds | Not qualified by this Catalyst 9200/9300 guide |
