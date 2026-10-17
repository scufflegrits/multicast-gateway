# Multicast Reference Guide — Windows (Server 2022 / Windows 11)

**Coverage: IPv4 multicast only.** IPv6/MLD configuration and validation are
outside this guide. mcgw itself retains its separate IPv4/IPv6 design scope.

| Field          | Detail                                  |
|----------------|-----------------------------------------|
| Version        | 1.0.1                                   |
| Last Updated   | 20261017                                |
| Author         | sysadmin                                |
| Filename       | MulticastReference-Windows_r1.0.1.md    |

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

| Version | Date     | Author   | Change Summary                                              |
|---------|----------|----------|-------------------------------------------------------------|
| Review 2 | 20261017 | scufflegrits | Second review corrections (F03, F05, F08, F09, F21, F22); see architecture review §7 |
| Review | 20261017 | scufflegrits | IPv4-only scope; technical corrections, clickable navigation, acronym and verification-source appendices; filename/version retained |
| 1.0.1   | 20250519 | sysadmin | Added section 4.4 — multicast interface selection on multi-homed Windows machines |
| 1.0.0   | 20250517 | sysadmin | Initial release                                             |

---

> **Domain Policy Note**
> Windows Firewall rules configured via PowerShell or the local firewall
> interface may be overridden or removed by Group Policy Objects (GPOs) applied
> from Active Directory. If firewall rules do not persist after a Group Policy
> refresh (`gpupdate /force`), the rules must be implemented at the GPO level
> by a domain administrator. All PowerShell commands in this guide assume local
> administrator rights. Domain-enforced firewall policies take precedence over
> locally configured rules. Verify effective policy with:
>
> ```
> Get-NetFirewallProfile | Select Name, Enabled
> gpresult /r /scope computer
> ```

---

## Table of Contents

- [Scope and command use](#scope-and-command-use)
- [Revision History](#revision-history)
- [1. Overview](#1-overview)
- [2. Windows Multicast Behavior](#2-windows-multicast-behavior)
  - [2.1 How Windows Handles Multicast](#21-how-windows-handles-multicast)
  - [2.2 IGMP Version on Windows](#22-igmp-version-on-windows)
  - [2.3 Differences Between Server 2022 and Windows 11](#23-differences-between-server-2022-and-windows-11)
- [3. VM NIC Configuration in Proxmox](#3-vm-nic-configuration-in-proxmox)
  - [3.1 Proxmox NIC and VLAN Tag](#31-proxmox-nic-and-vlan-tag)
  - [3.2 Verification at the Proxmox Host Level](#32-verification-at-the-proxmox-host-level)
- [4. Windows Network Interface Configuration](#4-windows-network-interface-configuration)
  - [4.1 Identifying the Correct Interface](#41-identifying-the-correct-interface)
  - [4.2 Assigning an IP Address](#42-assigning-an-ip-address)
  - [4.3 Verifying Multicast Capability](#43-verifying-multicast-capability)
  - [4.4 Multicast Interface Selection on Multi-Homed Machines](#44-multicast-interface-selection-on-multi-homed-machines)
    - [How Windows Selects the Multicast Interface](#how-windows-selects-the-multicast-interface)
    - [The Problem With Multiple Interfaces](#the-problem-with-multiple-interfaces)
    - [IGMP Join Interface Selection](#igmp-join-interface-selection)
    - [Mechanism 1 — Bind the Application to a Specific Interface (Recommended)](#mechanism-1--bind-the-application-to-a-specific-interface-recommended)
    - [Mechanism 2 — Add a Specific Multicast Route for the Interface](#mechanism-2--add-a-specific-multicast-route-for-the-interface)
    - [Mechanism 3 — Set a High Metric on Competing Default Routes](#mechanism-3--set-a-high-metric-on-competing-default-routes)
    - [Verifying Which Interface Multicast Is Using](#verifying-which-interface-multicast-is-using)
    - [Recommendation for This Environment](#recommendation-for-this-environment)
- [5. Windows Firewall — Multicast Rules](#5-windows-firewall--multicast-rules)
  - [5.1 Default Firewall Behavior for Multicast](#51-default-firewall-behavior-for-multicast)
  - [5.2 Creating Inbound Multicast Rules](#52-creating-inbound-multicast-rules)
  - [5.3 Creating Outbound Multicast Rules](#53-creating-outbound-multicast-rules)
  - [5.4 Verifying Firewall Rules](#54-verifying-firewall-rules)
  - [5.5 Removing Multicast Firewall Rules](#55-removing-multicast-firewall-rules)
- [6. Multicast Receiver Configuration](#6-multicast-receiver-configuration)
  - [6.1 Joining a Multicast Group via PowerShell](#61-joining-a-multicast-group-via-powershell)
  - [6.2 Using iperf2 for Windows as a Receiver](#62-using-iperf2-for-windows-as-a-receiver)
  - [6.3 Using Wireshark as a Passive Receiver](#63-using-wireshark-as-a-passive-receiver)
- [7. Multicast Sender Configuration](#7-multicast-sender-configuration)
  - [7.1 Using iperf2 for Windows as a Sender](#71-using-iperf2-for-windows-as-a-sender)
  - [7.2 Sending Multicast via PowerShell](#72-sending-multicast-via-powershell)
- [8. Required Tools and Installation](#8-required-tools-and-installation)
  - [8.1 iperf2 for Windows](#81-iperf2-for-windows)
  - [8.2 Wireshark](#82-wireshark)
  - [8.3 tshark](#83-tshark)
- [9. Testing and Verification](#9-testing-and-verification)
  - [9.1 Verification Commands — PowerShell](#91-verification-commands--powershell)
  - [9.2 Verification Commands — Wireshark and tshark](#92-verification-commands--wireshark-and-tshark)
  - [9.3 Worked End-to-End Test Scenario](#93-worked-end-to-end-test-scenario)
- [10. Troubleshooting](#10-troubleshooting)
  - [10.1 Multicast Not Leaving the Windows VM](#101-multicast-not-leaving-the-windows-vm)
  - [10.2 Multicast Not Arriving at the Windows VM](#102-multicast-not-arriving-at-the-windows-vm)
  - [10.3 IGMP Join Not Seen by Switch](#103-igmp-join-not-seen-by-switch)
  - [10.4 Multicast Works Briefly Then Stops](#104-multicast-works-briefly-then-stops)
  - [10.5 Firewall Blocking Multicast Despite Rules](#105-firewall-blocking-multicast-despite-rules)
- [11. Glossary](#11-glossary)
- [Appendix A — Acronyms and meanings](#appendix-a--acronyms-and-meanings)
- [Appendix B — Verification sources](#appendix-b--verification-sources)
  - [Qualification still required](#qualification-still-required)

## 1. Overview

This document covers multicast configuration for Windows Server 2022 and
Windows 11 virtual machines running on Proxmox VE in an environment where
intra-VLAN multicast is required between Windows VMs and physical clients
connected to Cisco Catalyst access layer switches.

The architecture is:

```
Windows VM (PVE0x, VLAN 2601)
    ↓ tap interface
vmbr999 Linux bridge (VLAN-aware, explicit snooping/flooding policy)
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
[Cisco guide](MulticastReference-Cisco_r1.0.0.md). The Proxmox bridge follows the explicit snooping/flooding policy in [Debian/Proxmox guide](MulticastReference-LinuxDebian_r1.0.3.md).

All commands in this guide are run in an elevated PowerShell session unless
otherwise noted. To open an elevated PowerShell session:

```
Right-click Start → Windows Terminal (Admin)
```

Or from an existing terminal:

```
Start-Process powershell -Verb RunAs
```

---

## 2. Windows Multicast Behavior

### 2.1 How Windows Handles Multicast

An application opens a UDP socket and explicitly joins a group on an interface.
Windows maintains host/interface state for those requests and performs IGMP
signaling. Closing a socket releases its memberships; another application's
membership may keep the host interested in the same group.

The same distinction applies on Linux: ordinary socket joins do not persist
independently after all owners close them. Administrative `autojoin` or a running
membership daemon are different mechanisms. A socket bound to a port has not
necessarily joined a multicast group. See sources W1 and W2.

### 2.2 IGMP Version on Windows

Inspect host configuration and actual membership/query packets; do not infer
active wire behavior solely from the OS name. Compatibility with an older
querier can affect reporting.

```powershell
Get-NetIPv4Protocol | Format-List *
```

Property names/availability depend on the installed networking module. Packet
capture is the check for the IGMP version actually used.

IGMPv3 supports source lists. A switch that snoops IGMPv3 reports need not have
an IGMPv3-capable **snooping querier**. Do not assume the illustrated Cisco querier
uses version 3; verify the selected platform/release and configuration (W3).

### 2.3 Differences Between Server 2022 and Windows 11

Both platforms provide multicast socket APIs and firewall controls. Record the
OS build, PowerShell/.NET version, adapter driver, effective firewall profiles,
and policy. Server versus desktop branding does not establish the active profile,
allowed traffic, or available third-party test binaries.

Use the PowerShell socket tests below as examples to qualify on each build;
no claim of identical behavior under every policy/update is made.

## 3. VM NIC Configuration in Proxmox

### 3.1 Proxmox NIC and VLAN Tag

For a Windows VM to participate in multicast on a specific VLAN, its NIC must
be connected to the VLAN-aware bridge with the correct VLAN tag. This is
configured in the VM's Proxmox configuration file.

Location of VM configuration files on the Proxmox host:

```
/etc/pve/qemu-server/<vmid>.conf
```

Example NIC configuration for a Windows VM on VLAN 2601:

```
net0: virtio=BC:24:11:AA:BB:CC,bridge=vmbr999,tag=2601
```

Key parameters:

```
bridge=vmbr999    Connects the VM NIC to the VLAN-aware bridge
tag=2601          The bridge presents VLAN 2601 to this NIC
                  The Windows guest sees a standard untagged Ethernet adapter
                  The bridge handles 802.1Q tagging toward the switch
```

The Windows VM does not see or need to configure 802.1Q VLAN tagging. The
NIC appears in Windows as a standard Ethernet adapter. All VLAN tagging is
handled transparently by the Proxmox bridge.

Note on NIC driver: The `virtio` NIC type provides the best performance and
is recommended. If the Windows VM does not have the VirtIO drivers installed,
use `e1000` as a fallback. VirtIO drivers for Windows are available from the
Fedora VirtIO driver repository and can be installed via the virtio-win ISO.

Install VirtIO drivers if using virtio NIC type:

```
# Download the virtio-win ISO on the Proxmox host
wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso \
  -O /var/lib/vz/template/iso/virtio-win.iso
```

Mount the ISO in the VM via the Proxmox interface and run the installer inside
Windows.

### 3.2 Verification at the Proxmox Host Level

Verify the tap interface for the Windows VM is up and associated with the
correct bridge:

```bash
# On the Proxmox host — replace 101 with the VM ID
ip link show tap101i0
bridge vlan show dev tap101i0
```

Capture traffic on the tap interface to verify multicast frames are passing
between the Windows VM and the bridge:

```bash
sudo tcpdump -i tap101i0 -nn -e multicast
```

Capture IGMP traffic specifically to verify Windows is sending joins:

```bash
sudo tcpdump -i tap101i0 -nn igmp
```

---

## 4. Windows Network Interface Configuration

### 4.1 Identifying the Correct Interface

Windows may present multiple network interfaces. Identify the interface
connected to the Proxmox bridge (the one that should carry multicast traffic).

List all interfaces with their index, name, and status:

```powershell
Get-NetAdapter | Select ifIndex, Name, Status, MacAddress, LinkSpeed
```

Match the MAC address shown against the MAC configured in the Proxmox VM NIC
configuration (`net0: virtio=BC:24:11:AA:BB:CC`).

Get the interface index for use in subsequent commands:

```powershell
$ifIndex = (Get-NetAdapter | Where-Object { $_.MacAddress -eq "BC-24-11-AA-BB-CC" }).ifIndex
Write-Host "Interface Index: $ifIndex"
```

Note: PowerShell displays MAC addresses with hyphens (`BC-24-11-AA-BB-CC`)
while Proxmox displays them with colons (`BC:24:11:AA:BB:CC`). Substitute
accordingly when matching.

### 4.2 Assigning an IP Address

A Windows interface must have an IP address to send or receive multicast.
Without a source IP, the Windows network stack will not send IGMP joins.

Assign a static IP address to the interface (replace values as appropriate):

```powershell
New-NetIPAddress `
  -InterfaceIndex $ifIndex `
  -IPAddress 192.168.1.10 `
  -PrefixLength 24
```

If no default gateway is needed (intra-VLAN only, no routing):

```powershell
New-NetIPAddress `
  -InterfaceIndex $ifIndex `
  -IPAddress 192.168.1.10 `
  -PrefixLength 24
# Omit -DefaultGateway to leave no gateway configured
```

Verify the IP address is assigned:

```powershell
Get-NetIPAddress -InterfaceIndex $ifIndex
```

IPv4-only coverage does not require disabling IPv6 on the host.

### 4.3 Verifying Multicast Capability

Inspect the intended NIC and IPv4 addressing, then run the explicit membership
test in section 6.1. A successful adapter listing or passive capture does not
prove application membership or delivery.

```powershell
Get-NetAdapter | Where-Object { $_.ifIndex -eq $ifIndex }
Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4
netsh interface ipv4 show joins
```

The join listing is host evidence, not proof that a particular application
socket received the feed. Check actual packets with Wireshark/tshark.

### 4.4 Multicast Interface Selection on Multi-Homed Machines

A multi-homed Windows machine has more than one active network interface. This
is common for VMs on Proxmox with separate NICs for management, data, and VLAN
access. Incorrect multicast interface selection is one of the most frequent
causes of multicast failure on Windows and must be understood and controlled
explicitly.

#### How Windows Selects the Multicast Interface

When the application does not select an outgoing multicast interface, inspect
Windows routing/default selection. Routing considers prefix specificity before
metrics; effective costs include route and interface metrics. A missing
239/8-specific route does not by itself imply the default route wins: another
multicast route may match.

```powershell
Get-NetRoute -AddressFamily IPv4
Get-NetIPInterface -AddressFamily IPv4
```

Confirm the actual outgoing interface using capture, rather than infer it from
default gateways alone.

#### The Problem With Multiple Interfaces

An illustrative VM has management, multicast-data and external NICs. If an
application leaves interface selection implicit, traffic can use an unintended
NIC. Inspect matching routes and socket settings; do not assume the NIC with
the cheapest default gateway necessarily wins.

#### IGMP Join Interface Selection

Receive membership specifies a group **and an interface**. If the application
omits the interface, the stack selects a default, which can be unsuitable.
Use the explicit local-interface overload in section 6.1. Setting an outgoing
multicast interface does not choose the receiving membership interface (W1).

#### Mechanism 1 — Bind the Application to a Specific Interface (Recommended)

Choose the socket operations separately:

| Operation | Purpose |
|---|---|
| Bind local endpoint | Select receive port / local source endpoint |
| `JoinMulticastGroup(group, localAddress)` | Select IPv4 membership interface |
| `IP_MULTICAST_IF` / `MulticastInterface` | Select outgoing IPv4 multicast interface |

A bind alone is not a replacement for either interface-specific operation. Use
the complete receiver/sender scripts in sections 6.1 and 7.2. They avoid reliance
on an unverified `%address` suffix or Linux-only device-binding option.

#### Mechanism 2 — Add a Specific Multicast Route for the Interface

Force all 239.0.0.0/8 traffic out a specific interface by adding an explicit
route. This is a system-wide setting that affects all applications on the
machine, not just one. Use this when the application does not support interface
binding.

```powershell
# Get the interface index for the VLAN 2601 NIC
$ifIndex = (Get-NetAdapter -Name "Ethernet 2").ifIndex

# Add a specific route for the multicast range via that interface
New-NetRoute `
  -DestinationPrefix 239.0.0.0/8 `
  -InterfaceIndex $ifIndex `
  -NextHop 0.0.0.0 `
  -RouteMetric 1
```

A /8 route is more specific than a default route. Compare equally specific
routes and effective interface/route costs; a metric value alone is not a
universal override.

Verify the route is in place:

```powershell
Get-NetRoute -DestinationPrefix 239.0.0.0/8
```

To remove the route if no longer needed:

```powershell
Remove-NetRoute -DestinationPrefix 239.0.0.0/8 -InterfaceIndex $ifIndex -Confirm:$false
```

#### Mechanism 3 — Set a High Metric on Competing Default Routes

Changing interface metrics can affect other traffic and only resolves choices
between otherwise comparable routes. Prefer explicit socket interface selection
or a deliberately scoped route. Do not change management/default-route costs
merely because multicast capture is empty.

#### Verifying Which Interface Multicast Is Using

The fastest way to identify which interface is carrying multicast or IGMP
traffic is to run tshark simultaneously on two interfaces:

```powershell
# Terminal 1 — watch the intended multicast interface
tshark -i "Ethernet 2" -f "igmp or host 239.1.1.1" -n

# Terminal 2 — watch a competing interface
tshark -i "Ethernet 3" -f "igmp or host 239.1.1.1" -n
```

Start the application and observe which tshark session shows activity. If
traffic appears on Ethernet 3 and not Ethernet 2, the wrong interface is being
used. Inspect both the application's socket interface settings (sections 6.1
and 7.2) and the routing table before applying Mechanism 1 or 2 above.

#### Recommendation for This Environment

1. Select the receiving membership interface and outgoing multicast interface
   explicitly in test applications.
2. Use a scoped multicast route only when required for an application relying
   on default selection; verify it does not redirect other feeds.
3. Capture on intended and competing NICs and inspect effective routing.
4. Do not assume a source bind or low interface metric independently enforces
   the intended multicast path.

## 5. Windows Firewall — Multicast Rules

### 5.1 Default Firewall Behavior for Multicast

Inspect effective firewall profiles, rules and organizational policy. A local
multicast join does not grant firewall permission. Permit only the required
UDP group/port and necessary membership signaling; a broad 239/8 all-port rule
is a lab alternative, not the preferred production policy.

Outbound permission also depends on policy. Adding allow rules does not defeat
an explicit block rule. Record current state before changing it and remove only
the specific test rules you created.

### 5.2 Creating Inbound Multicast Rules

Create an inbound rule permitting UDP traffic destined for the 239.0.0.0/8
range on a specific port. Replace the port number and group address range as
appropriate for your application.

Permit inbound UDP multicast for a specific group and port:

```powershell
New-NetFirewallRule `
  -DisplayName "Allow Inbound Multicast UDP 239.x.x.x port 5001" `
  -Direction Inbound `
  -Protocol UDP `
  -LocalAddress 239.0.0.0/8 `
  -LocalPort 5001 `
  -Action Allow `
  -Profile Any `
  -Enabled True
```

Permit inbound UDP multicast for all ports on the 239.x.x.x range (less
restrictive — use only in controlled environments):

```powershell
New-NetFirewallRule `
  -DisplayName "Allow Inbound Multicast UDP 239.x.x.x all ports" `
  -Direction Inbound `
  -Protocol UDP `
  -LocalAddress 239.0.0.0/8 `
  -LocalPort Any `
  -Action Allow `
  -Profile Any `
  -Enabled True
```

Permit inbound IGMP traffic (required for the network stack to process IGMP
queries from the upstream Cisco switch querier):

```powershell
New-NetFirewallRule `
  -DisplayName "Allow Inbound IGMP" `
  -Direction Inbound `
  -Protocol 2 `
  -Action Allow `
  -Profile Any `
  -Enabled True
```

Protocol number 2 is IGMP. Windows Firewall does not have a named protocol
alias for IGMP so the protocol number must be specified directly.

Inspect capture and effective policy before adding membership rules. Successful
initial reports do not prove later queries reach the host.

### 5.3 Creating Outbound Multicast Rules

Permit outbound UDP multicast for a specific group and port:

```powershell
New-NetFirewallRule `
  -DisplayName "Allow Outbound Multicast UDP 239.x.x.x port 5001" `
  -Direction Outbound `
  -Protocol UDP `
  -RemoteAddress 239.0.0.0/8 `
  -RemotePort 5001 `
  -Action Allow `
  -Profile Any `
  -Enabled True
```

Permit outbound UDP multicast for all ports on the 239.x.x.x range:

```powershell
New-NetFirewallRule `
  -DisplayName "Allow Outbound Multicast UDP 239.x.x.x all ports" `
  -Direction Outbound `
  -Protocol UDP `
  -RemoteAddress 239.0.0.0/8 `
  -RemotePort Any `
  -Action Allow `
  -Profile Any `
  -Enabled True
```

Permit outbound IGMP:

```powershell
New-NetFirewallRule `
  -DisplayName "Allow Outbound IGMP" `
  -Direction Outbound `
  -Protocol 2 `
  -Action Allow `
  -Profile Any `
  -Enabled True
```

### 5.4 Verifying Firewall Rules

List all firewall rules related to multicast:

```powershell
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*Multicast*" -or $_.DisplayName -like "*IGMP*" } |
  Select DisplayName, Direction, Enabled, Action |
  Format-Table -AutoSize
```

Verify the effective firewall profile currently active:

```powershell
Get-NetFirewallProfile | Select Name, Enabled, DefaultInboundAction, DefaultOutboundAction
```

`Test-NetConnection -Port` tests TCP, not multicast UDP; do not use it as
multicast evidence. Use the UDP scripts and captures below.

### 5.5 Removing Multicast Firewall Rules

Remove a specific rule by display name:

```powershell
Remove-NetFirewallRule -DisplayName "Allow Inbound Multicast UDP 239.x.x.x port 5001"
```

Remove only rules created for this test; a wildcard deletion can remove unrelated
production policy. Record rule names before making changes.

---

## 6. Multicast Receiver Configuration

### 6.1 Joining a Multicast Group via PowerShell

Save as `multicast-receive.ps1`. Select the local IPv4 address actually assigned
to the intended NIC. This test opens a UDP socket and joins a group; it does not
change persistent host routes. Stop with Ctrl+C.

```powershell
$group = [System.Net.IPAddress]::Parse("239.1.1.1")
$localIP = [System.Net.IPAddress]::Parse("192.168.1.20")
$port = 5001
$udpClient = [System.Net.Sockets.UdpClient]::new(
    [System.Net.Sockets.AddressFamily]::InterNetwork)
$udpClient.Client.ExclusiveAddressUse = $false
$udpClient.Client.SetSocketOption(
    [System.Net.Sockets.SocketOptionLevel]::Socket,
    [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)
$udpClient.Client.Bind([System.Net.IPEndPoint]::new(
    [System.Net.IPAddress]::Any, $port))
$udpClient.JoinMulticastGroup($group, $localIP)
$remoteEP = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
try {
    while ($true) {
        $bytes = $udpClient.Receive([ref]$remoteEP)
        Write-Host "$($remoteEP.Address):$($remoteEP.Port) bytes=$($bytes.Length)"
    }
} finally {
    $udpClient.Close()
}
```

Closing the socket releases its memberships. IGMP leave/report traffic depends
on protocol version, other memberships and compatibility state; do not demand
one leave packet per process exit. Packet capture and switch tables provide
additional evidence, not application payload validation.

### 6.2 Using iperf2 for Windows as a Receiver

**Use iperf2, not iperf3.** iperf3 does not support IP multicast (W4a/W5).
For deterministic multihomed testing, prefer the explicit PowerShell receiver
above. An iperf2 example, after qualifying the chosen Windows build:

```powershell
iperf.exe -s -u -B 239.1.1.1 -p 5001 -i 1
```

This example does not explicitly select the membership NIC. Check the tool's
version/help and captures before using it on a multihomed system; do not assume
Linux `%device` syntax works on Windows. Run a matching iperf2 sender, not a
PowerShell payload generator, when interpreting iperf2 loss/jitter statistics.

### 6.3 Using Wireshark as a Passive Receiver

Wireshark can capture multicast traffic without joining the group. This is
useful for verifying that multicast frames are arriving at the Windows VM at
the network adapter level, independent of whether any application has joined
the group.

Capture multicast traffic in Wireshark:

1. Open Wireshark with administrator privileges
2. Select the correct network interface (match to the Proxmox NIC MAC)
3. Enter the following display filter:

```
ip.dst >= 239.0.0.0 && ip.dst <= 239.255.255.255
```

Or filter for a specific group:

```
ip.dst == 239.1.1.1
```

Capture IGMP traffic to verify joins and queries:

```
igmp
```

Using tshark from the command line:

```
tshark.exe -i "Ethernet 2" -f "ip multicast" -n
```

Filter for a specific group with tshark:

```
tshark.exe -i "Ethernet 2" -f "host 239.1.1.1" -n
```

Note: Wireshark and tshark capture at the adapter level, before the Windows
Firewall. If Wireshark shows multicast arriving but the application does not
receive it, the firewall is one possible cause; also inspect socket membership/interface and buffers. See section 5.

---

## 7. Multicast Sender Configuration

### 7.1 Using iperf2 for Windows as a Sender

iperf2 supports multicast; iperf3 does not. Example for a qualified iperf2 build:

```powershell
iperf.exe -c 239.1.1.1 -u -b 1M -p 5001 -T 1 -t 30
```

Use a matching iperf2 receiver. The multicast TTL is `-T` in iperf2; do not copy
iperf3 options into this command. For an explicit NIC/source choice independent
of tool-specific options, use the PowerShell sender in section 7.2.

### 7.2 Sending Multicast via PowerShell

A PowerShell script can send multicast UDP packets to a group without a third-party traffic generator. Pair it with the PowerShell receiver,
not an iperf2 statistics parser.

Send multicast UDP packets using .NET UdpClient:

```powershell
# Configuration
$groupAddress = "239.1.1.1"
$port = 5001
$sourceIP = "192.168.1.10"   # IP of the local interface to send from
$message = "Multicast test packet"
$packetCount = 100
$intervalMs = 1000            # 1 second between packets

# Create UDP client bound to the local interface
$localEP = New-Object System.Net.IPEndPoint(
    [System.Net.IPAddress]::Parse($sourceIP), 0)
$udpClient = New-Object System.Net.Sockets.UdpClient($localEP)

# Select the outgoing IPv4 multicast interface independently of the bind
$udpClient.Client.SetSocketOption(
    [System.Net.Sockets.SocketOptionLevel]::IP,
    [System.Net.Sockets.SocketOptionName]::MulticastInterface,
    [byte[]]([System.Net.IPAddress]::Parse($sourceIP).GetAddressBytes()))

# Set multicast TTL
$udpClient.Client.SetSocketOption(
    [System.Net.Sockets.SocketOptionLevel]::IP,
    [System.Net.Sockets.SocketOptionName]::MulticastTimeToLive,
    1
)

# Remote endpoint (multicast group)
$remoteEP = New-Object System.Net.IPEndPoint(
    [System.Net.IPAddress]::Parse($groupAddress), $port)

Write-Host "Sending $packetCount packets to $groupAddress`:$port from $sourceIP"

for ($i = 1; $i -le $packetCount; $i++) {
    $payload = [System.Text.Encoding]::UTF8.GetBytes("$message #$i")
    $udpClient.Send($payload, $payload.Length, $remoteEP) | Out-Null
    Write-Host "Sent packet $i"
    Start-Sleep -Milliseconds $intervalMs
}

$udpClient.Close()
Write-Host "Done."
```

Save as `multicast-send.ps1` and run with:

```powershell
powershell -File multicast-send.ps1
```

---

## 8. Required Tools and Installation

### 8.1 iperf2 for Windows

Obtain an iperf2 Windows release from the upstream project (W5), verify release
provenance, and record its version. Do not use an unverified package-manager ID
or a hard-coded “latest” executable URL as deployment instructions.

```powershell
iperf.exe --version
iperf.exe --help
```

The built-in PowerShell/.NET examples are the alternative when iperf2 is absent.
ESnet does not officially support iperf3 on Windows and recommends iperf2 (W4).
An installed iperf3 binary is not a multicast test tool.

### 8.2 Wireshark

Install Wireshark via winget:

```powershell
winget install -e --id WiresharkFoundation.Wireshark
```

Manual installation: Download the installer from `https://www.wireshark.org`
and run it. During installation, ensure the Npcap driver is installed — it is
required for packet capture on Windows.

Verify Wireshark is installed:

```powershell
Get-Command wireshark -ErrorAction SilentlyContinue
```

### 8.3 tshark

tshark is installed as part of the Wireshark package. After installing
Wireshark, tshark is available at:

```
C:\Program Files\Wireshark\tshark.exe
```

Add to PATH if not already present:

```powershell
[System.Environment]::SetEnvironmentVariable(
    "PATH",
    [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";C:\Program Files\Wireshark",
    "Machine"
)
```

Verify tshark is accessible:

```powershell
tshark --version
```

List available capture interfaces:

```powershell
tshark -D
```

---

## 9. Testing and Verification

### 9.1 Verification Commands — PowerShell

List all network interfaces and their status:

```powershell
Get-NetAdapter | Select Name, Status, MacAddress, LinkSpeed | Format-Table -AutoSize
```

Show IP addresses assigned to all interfaces:

```powershell
Get-NetIPAddress -AddressFamily IPv4 | Select InterfaceAlias, IPAddress, PrefixLength
```

Show all multicast groups currently joined by Windows:

```powershell
netsh interface ip show joins
```

Show bound UDP endpoints (a bind alone does not prove multicast membership):

```powershell
Get-NetUDPEndpoint | Where-Object { $_.LocalPort -eq 5201 } |
  Select LocalAddress, LocalPort, OwningProcess
```

Show the process owning a specific port:

```powershell
$proc = Get-NetUDPEndpoint | Where-Object { $_.LocalPort -eq 5201 } |
  Select -First 1 -ExpandProperty OwningProcess
Get-Process -Id $proc | Select Name, Id
```

Test basic network connectivity to a unicast address on the same VLAN:

```powershell
Test-NetConnection -ComputerName 192.168.1.20 -InformationLevel Detailed
```

Show the full IPv4 routing table:

```powershell
Get-NetRoute -AddressFamily IPv4 | Sort-Object DestinationPrefix
```

Identify the most specific prefix covering the actual group (for example
239.1.1.1). It may be a 239/8 route, a broader multicast route such as
224.0.0.0/4, or the default route; among equally specific routes compare
effective route plus interface metrics ([4.4](#44-multicast-interface-selection-on-multi-homed-machines)).
A socket that sets its outgoing multicast interface
([7.2](#72-sending-multicast-via-powershell)) is not governed by this route
choice. The absence of a `239*` entry is not by itself a fault. Add a scoped multicast route only as a deliberate choice
(section 4.4, Mechanism 2, including its removal command).

### 9.2 Verification Commands — Wireshark and tshark

List available interfaces for capture:

```powershell
tshark -D
```

Capture all multicast traffic on a specific interface (replace `\Device\NPF_{GUID}`
with the interface identifier from `tshark -D`):

```powershell
tshark -i "Ethernet 2" -f "ip multicast" -n
```

Capture IGMP traffic only:

```powershell
tshark -i "Ethernet 2" -f "igmp" -n
```

Capture traffic for a specific multicast group:

```powershell
tshark -i "Ethernet 2" -f "host 239.1.1.1" -n
```

Capture and write to a file for later analysis:

```powershell
tshark -i "Ethernet 2" -f "ip multicast" -n -w C:\Captures\multicast.pcap
```

Open the capture file in Wireshark:

```powershell
wireshark C:\Captures\multicast.pcap
```

### 9.3 Worked End-to-End Test Scenario

| Role | Example |
|---|---|
| Sender | Windows VM, data NIC `192.168.1.10`, VLAN 2601 |
| Receiver | Windows destination, data NIC `192.168.1.20`, same VLAN |
| Test feed | Group `239.1.1.1`, UDP port `5001` |

| Step | Action | Evidence |
|---|---|---|
| 1 | Verify both data NICs/VLANs and firewall policy | Correct local addresses and permitted UDP/membership traffic |
| 2 | Inspect bridge snooping/MDB and actual querier | Either deliberately configured flooding mode or healthy snooping; no mandatory bridge-local querier |
| 3 | Run section 6.1 receiver on destination | Socket joins using destination's data-interface address |
| 4 | Inspect switch membership and capture IGMP | Receiver membership visible; a short missing report capture is inconclusive |
| 5 | Run section 7.2 sender on VM | Explicit outgoing multicast interface and source endpoint |
| 6 | Capture at VM, host uplink and destination | Trace matching UDP payloads and distinguish capture from socket delivery |
| 7 | Confirm receiver output | Received endpoint and payload length; this is a functional test, not a throughput benchmark |

Use iperf2 at **both** ends for rate/loss/jitter benchmarking, after qualifying
its interface selection. A Linux physical receiver can instead use mcjoin with
an explicitly selected interface; verify common group/port. Do not mix a raw
PowerShell sender with iperf2 measurement payloads.

The Proxmox bridge may keep snooping enabled when queries/MDB are healthy.
Disabling it is an optional flooding tradeoff, not a prerequisite for the test.

## 10. Troubleshooting

### 10.1 Multicast Not Leaving the Windows VM

Symptom: tshark on the Windows VM shows no outbound multicast traffic when
iperf2 or the PowerShell sender is running.

Step 1 — Verify the interface has an IP address:

```powershell
Get-NetIPAddress -AddressFamily IPv4 | Select InterfaceAlias, IPAddress
```

Without a source IP, Windows will not send multicast frames.

Step 2 — Identify the route that applies to the group:

```powershell
Get-NetRoute -AddressFamily IPv4 | Sort-Object DestinationPrefix
```

Identify the most specific prefix covering the actual group (for example
239.1.1.1). It may be a 239/8 route, a broader multicast route such as
224.0.0.0/4, or the default route; among equally specific routes compare
effective route plus interface metrics ([4.4](#44-multicast-interface-selection-on-multi-homed-machines)).
A socket that sets its outgoing multicast interface
([7.2](#72-sending-multicast-via-powershell)) is not governed by this route
choice. The absence of a `239*` entry is not by itself a fault. If the sender does not set its outgoing interface and the
applicable route selects the wrong interface, prefer fixing the socket (Step 3);
add a scoped route only deliberately (section 4.4, Mechanism 2).

Step 3 — Verify the application is binding to the correct interface. If the
Windows VM has multiple NICs, the application may be sending via the wrong one.
Use the explicit multicast-interface socket setting in section 7.2; a source bind alone is not interface enforcement.

Step 4 — Verify outbound firewall rules are not blocking multicast UDP:

```powershell
Get-NetFirewallRule | Where-Object {
  $_.Direction -eq "Outbound" -and $_.Enabled -eq "True" -and $_.Action -eq "Block"
} | Select DisplayName
```

### 10.2 Multicast Not Arriving at the Windows VM

Symptom: tshark on the Windows VM shows multicast frames arriving (visible in
the raw capture) but the iperf2 server or PowerShell receiver reports nothing.

Step 1 — Verify the inbound firewall rule is present and enabled:

```powershell
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*Multicast*" } |
  Select DisplayName, Direction, Enabled, Action
```

Step 2 — Verify the Windows Firewall profile. Rules created with `-Profile Any`
apply to all profiles. If rules were created for a specific profile (Domain,
Private, or Public) and the active profile is different, the rules will not
apply:

```powershell
Get-NetFirewallProfile | Select Name, Enabled
(Get-NetConnectionProfile).NetworkCategory
```

Step 3 — Prefer scoped diagnosis: enable drop logging (section 10.5, Step 4)
and inspect the inbound rules that match the group and UDP port. If a controlled
disable test is still needed, record each profile's original state and restore
it in `finally`, rather than re-enabling every profile afterwards:

```powershell
$profiles = 'Domain', 'Private', 'Public'
$saved = Get-NetFirewallProfile -Profile $profiles | Select-Object Name, Enabled
try {
  Set-NetFirewallProfile -Profile $profiles -Enabled False
  Start-Sleep -Seconds 30   # bounded observation window for the receiver
}
finally {
  foreach ($p in $saved) { Set-NetFirewallProfile -Profile $p.Name -Enabled $p.Enabled }
}
Get-NetFirewallProfile | Select-Object Name, Enabled
```

`finally` does not run if the PowerShell process itself is killed; confirm the
final state. If multicast arrives only during the test, the firewall is
involved: add or correct a scoped rule (section 5). Group Policy can override
local profile settings.

Step 4 — Verify on the Proxmox host that traffic is arriving at the tap
interface:

```bash
sudo tcpdump -i tap<vmid>i0 -nn host 239.1.1.1
```

If traffic appears on the tap but not in the Windows VM, the issue is within
the Windows guest (firewall, interface binding, or application).

Step 5 — Verify the application has joined the group. Check netsh:

```powershell
netsh interface ip show joins
```

The group 239.1.1.1 should appear in the output while the receiving application
is running.

### 10.3 IGMP Join Not Seen by Switch

Symptom: The Windows application is running and has joined the group, but
`show ip igmp snooping groups vlan 2601` on SWITCH01 does not show the
Windows VM's port.

Step 1 — Verify the IGMP join is being sent by the Windows VM using tshark:

```powershell
tshark -i "Ethernet 2" -f "igmp" -n
```

A membership report for 239.1.1.1 is sent when the group is first joined and
afterwards mainly in response to queries. Under IGMPv2 a host may also suppress
its report when it hears another member's report for the same group (W12). A
short capture without a report is therefore not proof that the join failed.
Capture across the join itself, or for at least one full query interval, and
correlate with:

- `netsh interface ip show joins` for the interface
- the owning socket and process (`Get-NetUDPEndpoint`)
- no error from iperf2 or the PowerShell script's join call
- the IGMP version actually seen on the wire

Step 2 — Verify the IGMP outbound firewall rule is present:

```powershell
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*IGMP*" } |
  Select DisplayName, Direction, Enabled, Action
```

Step 3 — Capture on the Proxmox tap and bond interfaces to trace where the
IGMP join stops:

```bash
# On PVE04 — verify the join leaves the tap
sudo tcpdump -i tap<vmid>i0 -nn igmp

# Verify it crosses the bond
sudo tcpdump -i bond999 -nn igmp
```

### 10.4 Multicast Works Briefly Then Stops

Symptom: Multicast is received initially but stops after 60–300 seconds.

A common hypothesis is membership aging: queries are not reaching the VM, or
its reports are not reaching the switch. Other candidates include querier or
snooping state changes on the switch, the application leaving the group, and
a path or interface change. Correlate local joins and socket owners, captures
spanning complete query intervals, and switch snooping/querier state before
settling on a cause.

Step 1 — Capture IGMP on the Windows VM to verify queries are arriving:

```powershell
tshark -i "Ethernet 2" -f "igmp" -n
```

You should see periodic IGMP general queries from the querier address
(10.32.204.254 for SWITCH01). If queries are arriving but membership times
out, the Windows stack may not be responding correctly.

Step 2 — Verify the inbound IGMP firewall rule is present. If IGMP queries
are blocked inbound, Windows cannot process them and will not send reports:

```powershell
Get-NetFirewallRule -DisplayName "Allow Inbound IGMP" | Select Enabled, Action
```

Step 3 — Verify the application is still running. Socket-held membership ends
when the socket closes. If no other local socket still holds the group on that
interface, the stack normally sends a leave; whether and when the switch removes
the port depends on its leave processing (last-member queries or immediate
leave) and aging policy. Another socket on the host can keep the interface's
aggregate membership alive after one application exits.

```powershell
Get-Process -Name iperf -ErrorAction SilentlyContinue
```

Step 4 — If using the PowerShell receiver script, verify it is still executing
and has not thrown an exception that caused it to exit the receive loop.

### 10.5 Firewall Blocking Multicast Despite Rules

Symptom: Firewall rules appear correct but multicast is still blocked.

Step 1 — Verify the active firewall profile matches the profile the rules are
applied to:

```powershell
# Show active profile
(Get-NetConnectionProfile).NetworkCategory

# Show rules by profile
Get-NetFirewallRule | Where-Object {
  $_.DisplayName -like "*Multicast*"
} | Select DisplayName, Profile, Enabled, Action
```

If the active profile is Public but rules are set to Domain or Private, they
will not apply. Recreate the rules with `-Profile Any`.

Step 2 — Check for conflicting explicit block rules:

```powershell
Get-NetFirewallRule | Where-Object {
  $_.Action -eq "Block" -and $_.Direction -eq "Inbound" -and $_.Enabled -eq "True"
} | Select DisplayName, Profile | Format-Table -AutoSize
```

An explicit block rule overrides any conflicting explicit allow rule,
regardless of which is more specific (the only exception is an allow rule
configured for authenticated bypass). A block rule for all inbound UDP therefore
overrides an allow rule for multicast UDP. Explicit allow rules do override the
profile's default inbound block, and rules from local and Group Policy stores
are merged according to policy settings (W10).

Step 3 — Check for domain GPO overrides:

```powershell
gpresult /r /scope computer | Select-String -Pattern "Firewall"
```

If Group Policy is managing the firewall, local rules may be ignored entirely.
Contact the domain administrator to have the multicast rules added at the GPO
level.

Step 4 — Enable Windows Firewall audit logging to capture blocked traffic:

```powershell
# Record current logging settings so they can be restored afterwards
Get-NetFirewallProfile | Select-Object Name, LogBlocked, LogFileName
Set-NetFirewallProfile -Profile Domain,Private,Public -LogBlocked True `
  -LogFileName "C:\Windows\System32\LogFiles\Firewall\pfirewall.log"
```

Limit `-Profile` to the active profile if the others should stay unchanged.

Then check the log for blocked multicast entries:

```powershell
Get-Content "C:\Windows\System32\LogFiles\Firewall\pfirewall.log" |
  Where-Object { $_ -match "239\." }
```

---

## 11. Glossary

| Term                  | Definition                                                                      |
|-----------------------|---------------------------------------------------------------------------------|
| GPO                   | Group Policy Object. Active Directory policy applied to computers or users.     |
| IGMP                  | Internet Group Management Protocol. Used by hosts to join multicast groups.     |
| IGMPv3 | IGMP version supporting source lists; verify effective wire version. |
| iperf2 | Traffic generator with multicast support; use matching endpoints. |
| iperf3 | Separate tool without IP multicast support; not used for these tests. |
| Multicast Group       | An IP address in the 224.0.0.0/4 range representing a set of receivers.         |
| netsh                 | Windows network configuration command-line tool.                                |
| Npcap                 | Windows packet capture driver required by Wireshark and tshark.                 |
| PowerShell            | Windows task automation and configuration management framework.                 |
| Proxmox VE            | Open-source hypervisor platform. Hosts Windows VMs connected via vmbr999.       |
| tap interface         | Virtual network interface on the Proxmox host connecting a VM to the bridge.    |
| tshark                | Command-line Wireshark for packet capture and dissection.                       |
| TTL                   | Time To Live. Multicast TTL of 1 limits traffic to the local subnet.            |
| UdpClient             | .NET class for sending and receiving UDP datagrams including multicast.          |
| VirtIO                | Paravirtualized device driver framework. Recommended NIC type for Proxmox VMs.  |
| vmbr999               | VLAN-aware Linux bridge on PVE hosts. snooping/flooding policy selected explicitly.     |
| Wireshark             | GUI packet capture and analysis tool.                                           |
| Windows Firewall      | Built-in stateful firewall in Windows. Filters inbound and outbound traffic.    |
| winget                | Windows Package Manager. Package-manager tooling; verify package IDs/provenance before use.                  |
| 239.0.0.0/8           | Administratively scoped multicast range. Administratively scoped; configured boundaries enforce scope.    |

## Appendix A — Acronyms and meanings

Literal command/API identifiers, interface names and lab device names are not
acronyms. Product names (such as IOS XE, ESXi and VirtIO) identify platforms;
use the vendor documentation for their release-specific behavior.

| Term | Meaning |
|---|---|
| API | Application Programming Interface |
| GUI | Graphical User Interface |
| ID | Identifier |
| IGMP | Internet Group Management Protocol |
| IP | Internet Protocol |
| IPv4 | Internet Protocol version 4 |
| IPv6 | Internet Protocol version 6 (outside this guide's configuration coverage) |
| ISO | ISO disk-image format (optical-media image) |
| LACP | Link Aggregation Control Protocol |
| MAC | Media Access Control |
| MDB | Multicast Database |
| MLD | Multicast Listener Discovery (outside this guide's configuration coverage) |
| NIC | Network Interface Card |
| OS | Operating System |
| PVE | Proxmox Virtual Environment |
| TCP | Transmission Control Protocol |
| TTL | Time to Live |
| UDP | User Datagram Protocol |
| URL | Uniform Resource Locator |
| UTF8 | Unicode Transformation Format — 8-bit |
| VE | Virtual Environment |
| VLAN | Virtual Local Area Network |
| VM | Virtual Machine |
| GPO | Group Policy Object |
| GUID | Globally Unique Identifier |

## Appendix B — Verification sources

Accessed/reviewed 2026-10-17. These primary sources support the corrected
mechanisms, not a claim that every command or platform was tested. Configuration
choices and example topology are project guidance. No hardware/VM lab validation
was performed during this revision. Pin tool versions and verify installed help,
service units, policy and vendor release notes before deployment.

| ID | Primary source | Verification scope |
|---|---|---|
| W1 | [Microsoft IPv4 socket options](https://learn.microsoft.com/en-us/windows/win32/winsock/ipproto-ip-socket-options) | Separate outgoing interface, membership interface, and socket options |
| W2 | [Microsoft UdpClient.JoinMulticastGroup](https://learn.microsoft.com/en-us/dotnet/api/system.net.sockets.udpclient.joinmulticastgroup?view=net-9.0) | Explicit IPv4 local-address membership overload; scripts require platform qualification |
| W3 | [Catalyst 9300 IOS XE 17.15.x multicast guide](https://www.cisco.com/c/en/us/td/docs/switches/lan/catalyst9300/software/release/17-15/configuration_guide/ip_mcast_rtng/b_1715_ip_mcast_rtng_9300_cg.pdf) | Do not equate IGMPv3 snooping with snooping-querier version |
| W4 | [ESnet iperf3 FAQ](https://software.es.net/iperf/faq.html) | Windows support position and recommendation of iperf2 |
| W4a | [ESnet maintainer response on multicast](https://github.com/esnet/iperf/issues/617) | iperf3 lacks IP multicast support |
| W5 | [Upstream iperf2 manual](https://iperf2.sourceforge.io/iperf-manpage.html) | Multicast tool/mode/options; qualify chosen Windows build |
| W6 | [Wireshark tshark manual](https://www.wireshark.org/docs/man-pages/tshark.html) | Capture selection, filters and bounds |
| W7 | [Linux bridge documentation](https://www.kernel.org/doc/html/latest/networking/bridge.html) | Underlying Proxmox bridge membership/snooping concepts |
| W8 | [Linux IPv4 socket manual](https://man7.org/linux/man-pages/man7/ip.7.html) | Linux comparison: socket joins versus administrative/daemon-held membership |
| W9 | [Microsoft route command](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/route_ws2008/) | Broad multicast route example; inspect installed routes rather than assume an automatic 239/8 entry |
| W10 | [Microsoft Windows Firewall rules](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/rules) | Explicit block/allow precedence and policy merging |
| W11 | [Microsoft Set-NetFirewallProfile](https://learn.microsoft.com/en-us/powershell/module/netsecurity/set-netfirewallprofile?view=windowsserver2025-ps) | Documented `-Profile` selection and property controls; confirm installed cmdlet version |
| W12 | [RFC 2236, section 3](https://www.rfc-editor.org/rfc/rfc2236.html#section-3) | IGMPv2 report suppression and leave processing; determine the actual wire version |
| G1 | [RFC 2365 — Administratively Scoped IP Multicast](https://www.rfc-editor.org/rfc/rfc2365.html) | 239/8 scope requires configured administrative boundaries; it is not inherent authentication or isolation |

### Qualification still required

| Evidence | Status |
|---|---|
| Exact OS/device/software versions and effective policy | Record and test at the site |
| Commands/scripts and complete data path | Not executed during this review |
| Throughput, loss, failover and recovery | Not measured; examples are not guarantees |
| IPv6/MLD | Explicitly outside this guide |
