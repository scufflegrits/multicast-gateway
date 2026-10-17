# Multicast Reference Guide — Windows (Server 2022 / Windows 11)

| Field          | Detail                                  |
|----------------|-----------------------------------------|
| Version        | 1.0.1                                   |
| Last Updated   | 20250519                                |
| Author         | sysadmin                                |
| Filename       | MulticastReference-Windows_r1.0.1.md    |

---

## Revision History

| Version | Date     | Author   | Change Summary                                              |
|---------|----------|----------|-------------------------------------------------------------|
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

1. [Overview](#1-overview)
2. [Windows Multicast Behavior](#2-windows-multicast-behavior)
   - 2.1 [How Windows Handles Multicast](#21-how-windows-handles-multicast)
   - 2.2 [IGMP Version on Windows](#22-igmp-version-on-windows)
   - 2.3 [Differences Between Server 2022 and Windows 11](#23-differences-between-server-2022-and-windows-11)
3. [VM NIC Configuration in Proxmox](#3-vm-nic-configuration-in-proxmox)
   - 3.1 [Proxmox NIC and VLAN Tag](#31-proxmox-nic-and-vlan-tag)
   - 3.2 [Verification at the Proxmox Host Level](#32-verification-at-the-proxmox-host-level)
4. [Windows Network Interface Configuration](#4-windows-network-interface-configuration)
   - 4.1 [Identifying the Correct Interface](#41-identifying-the-correct-interface)
   - 4.2 [Assigning an IP Address](#42-assigning-an-ip-address)
   - 4.3 [Verifying Multicast Capability](#43-verifying-multicast-capability)
   - 4.4 [Multicast Interface Selection on Multi-Homed Machines](#44-multicast-interface-selection-on-multi-homed-machines)
5. [Windows Firewall — Multicast Rules](#5-windows-firewall--multicast-rules)
   - 5.1 [Default Firewall Behavior for Multicast](#51-default-firewall-behavior-for-multicast)
   - 5.2 [Creating Inbound Multicast Rules](#52-creating-inbound-multicast-rules)
   - 5.3 [Creating Outbound Multicast Rules](#53-creating-outbound-multicast-rules)
   - 5.4 [Verifying Firewall Rules](#54-verifying-firewall-rules)
   - 5.5 [Removing Multicast Firewall Rules](#55-removing-multicast-firewall-rules)
6. [Multicast Receiver Configuration](#6-multicast-receiver-configuration)
   - 6.1 [Joining a Multicast Group via PowerShell](#61-joining-a-multicast-group-via-powershell)
   - 6.2 [Using iperf3 for Windows as a Receiver](#62-using-iperf3-for-windows-as-a-receiver)
   - 6.3 [Using Wireshark as a Passive Receiver](#63-using-wireshark-as-a-passive-receiver)
7. [Multicast Sender Configuration](#7-multicast-sender-configuration)
   - 7.1 [Using iperf3 for Windows as a Sender](#71-using-iperf3-for-windows-as-a-sender)
   - 7.2 [Sending Multicast via PowerShell](#72-sending-multicast-via-powershell)
8. [Required Tools and Installation](#8-required-tools-and-installation)
   - 8.1 [iperf3 for Windows](#81-iperf3-for-windows)
   - 8.2 [Wireshark](#82-wireshark)
   - 8.3 [tshark](#83-tshark)
9. [Testing and Verification](#9-testing-and-verification)
   - 9.1 [Verification Commands — PowerShell](#91-verification-commands--powershell)
   - 9.2 [Verification Commands — Wireshark and tshark](#92-verification-commands--wireshark-and-tshark)
   - 9.3 [Worked End-to-End Test Scenario](#93-worked-end-to-end-test-scenario)
10. [Troubleshooting](#10-troubleshooting)
    - 10.1 [Multicast Not Leaving the Windows VM](#101-multicast-not-leaving-the-windows-vm)
    - 10.2 [Multicast Not Arriving at the Windows VM](#102-multicast-not-arriving-at-the-windows-vm)
    - 10.3 [IGMP Join Not Seen by Switch](#103-igmp-join-not-seen-by-switch)
    - 10.4 [Multicast Works Briefly Then Stops](#104-multicast-works-briefly-then-stops)
    - 10.5 [Firewall Blocking Multicast Despite Rules](#105-firewall-blocking-multicast-despite-rules)
11. [Glossary](#11-glossary)

---

## 1. Overview

This document covers multicast configuration for Windows Server 2022 and
Windows 11 virtual machines running on Proxmox VE in an environment where
intra-VLAN multicast is required between Windows VMs and physical clients
connected to Cisco Catalyst access layer switches.

The architecture is:

```
Windows VM (PVE0x, VLAN 2601)
    ↓ tap interface
vmbr999 Linux bridge (VLAN-aware, bridge-mcsnooping 0)
    ↓ bond999 (LACP 802.3ad)
SWITCH01
    ↓ trunk
SWITCH02
    ↓ access port Gi1/0/1
Physical client (VLAN 2601)
```

Multicast is intra-VLAN only. No inter-VLAN multicast routing is required.
Multicast group addresses are in the 239.0.0.0/8 administratively scoped range.
The Cisco switches handle IGMP snooping and querier duties as described in
MulticastReference-Cisco_r1.0.0.md. The Proxmox bridge is configured to be
transparent to multicast as described in MulticastReference-Linux_r1.0.0.md.

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

Windows implements IGMP at the network stack level via the TCP/IP driver. When
an application joins a multicast group using the Windows Sockets API
(`setsockopt` with `IP_ADD_MEMBERSHIP`), the kernel automatically sends an
IGMP membership report on the bound interface. No separate daemon or service
is required for basic multicast group membership.

Key behaviors:

```
- IGMP joins are sent automatically when an application joins a group
- IGMP leaves are sent automatically when the application leaves or exits
- Windows does not act as a multicast router by default
- Windows does not send IGMP queries — it is always a host, never a querier
- Multicast group membership is per-socket, not per-interface at the OS level
- Multiple applications can join the same group independently
```

This is an important distinction from Linux, where the kernel maintains
interface-level multicast group membership that persists independently of
individual applications. On Windows, if the application that joined the group
exits, the IGMP leave is sent and the group is left. There is no equivalent of
smcroute for persistent OS-level group membership on Windows without a running
application.

### 2.2 IGMP Version on Windows

Windows uses IGMPv3 by default on modern versions. IGMPv3 is backward
compatible with IGMPv2 queriers. The upstream Cisco switch querier configured
in this environment uses IGMPv3, which is compatible.

Verify the IGMP version in use:

```powershell
Get-NetIPv4Protocol | Select -ExpandProperty IGMPVersion
```

Expected output on modern Windows:

```
Version3
```

IGMPv3 supports source-specific multicast (SSM), allowing a receiver to
specify both the multicast group and the source IP it wants to receive from.
For any-source multicast (ASM) with 239.x.x.x groups, IGMPv3 operates in
exclude mode with an empty exclude list, which is functionally equivalent to
an IGMPv2 join.

### 2.3 Differences Between Server 2022 and Windows 11

For multicast purposes, Windows Server 2022 and Windows 11 behave identically
at the network stack level. Both use IGMPv3, both implement the same Windows
Firewall architecture, and both support the same PowerShell networking
commandlets.

Differences that may be relevant:

| Area                   | Windows Server 2022                  | Windows 11                          |
|------------------------|--------------------------------------|-------------------------------------|
| Firewall default       | Public profile active by default     | Domain/Private profile if joined    |
| Network discovery      | Disabled by default                  | Enabled on Private networks         |
| PowerShell version     | 5.1 (7.x installable)                | 5.1 (7.x installable)               |
| Hyper-V network stack  | Present if Hyper-V role installed    | Present on Pro/Enterprise editions  |
| iperf3 availability    | Manual install required              | Manual install required             |

For all commands in this guide, behavior is identical between the two platforms
unless explicitly noted.

---

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

Disable IPv6 on the interface if not needed (reduces noise in packet captures):

```powershell
Disable-NetAdapterBinding -Name (Get-NetAdapter -InterfaceIndex $ifIndex).Name `
  -ComponentID ms_tcpip6
```

### 4.3 Verifying Multicast Capability

Verify the interface supports multicast:

```powershell
Get-NetAdapter -InterfaceIndex $ifIndex | Select Name, PromiscuousMode, MulticastList
```

Verify the interface is a member of the standard link-local multicast groups
(these are joined automatically by Windows):

```powershell
Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 | Select InterfaceAlias
netsh interface ip show joins
```

The output of `netsh interface ip show joins` lists all multicast groups the
interface has joined. Initially you will see standard Windows groups such as
224.0.0.1 (all hosts) and 239.255.255.250 (SSDP/UPnP). Application-joined
groups appear here when the application is running.

### 4.4 Multicast Interface Selection on Multi-Homed Machines

A multi-homed Windows machine has more than one active network interface. This
is common for VMs on Proxmox with separate NICs for management, data, and VLAN
access. Incorrect multicast interface selection is one of the most frequent
causes of multicast failure on Windows and must be understood and controlled
explicitly.

#### How Windows Selects the Multicast Interface

Windows does not have a dedicated multicast interface setting. It selects the
outbound interface for multicast traffic the same way it selects the interface
for any other IP traffic — by consulting the routing table and picking the
interface associated with the lowest metric route that covers the destination.

For multicast, the destination is in the 239.0.0.0/8 range. Windows looks for
a route matching that range:

```powershell
Get-NetRoute -AddressFamily IPv4 | Where-Object {
    $_.DestinationPrefix -like "224*" -or $_.DestinationPrefix -like "239*"
}
```

If no specific multicast route exists, Windows falls back to the default route
(0.0.0.0/0). Whichever interface owns the lowest-metric default route becomes
the multicast interface. On a machine with multiple NICs and multiple default
gateways, this is almost always the wrong interface for intra-VLAN multicast.

#### The Problem With Multiple Interfaces

Consider a Windows VM with three NICs:

```
Ethernet 1 — management,  IP 10.32.200.x,  gateway 10.32.200.254, metric 25
Ethernet 2 — VLAN 2601,   IP 192.168.1.10, no gateway,            metric 25
Ethernet 3 — external,    IP 10.0.0.x,     gateway 10.0.0.1,      metric 5
```

When an application sends multicast to 239.1.1.1 without explicitly binding to
an interface, Windows picks Ethernet 3 because it has the lowest metric default
route. The multicast traffic exits the wrong NIC, never reaches VLAN 2601, and
the physical client on SWITCH02 receives nothing.

#### IGMP Join Interface Selection

The same routing table logic applies to IGMP joins. When an application joins
239.1.1.1, the IGMP membership report is sent out whichever interface the
routing table selects for that group — not necessarily the interface the
application intends to receive traffic on:

```
Application joins 239.1.1.1
    ↓
Windows consults routing table for 239.1.1.1
    ↓
Lowest metric route wins — may be the wrong interface
    ↓
IGMP join exits Ethernet 3 instead of Ethernet 2
    ↓
SWITCH01 sees no join on VLAN 2601
    ↓
Multicast never delivered to the physical client VLAN
```

This is why explicitly binding to the correct interface is essential on
multi-homed Windows machines, not just a best practice.

#### Mechanism 1 — Bind the Application to a Specific Interface (Recommended)

The application specifies the local IP address of the intended interface via
the `IP_MULTICAST_IF` socket option. This overrides the routing table for that
socket only and is the correct, portable approach.

In iperf3, use the `-B` flag:

```powershell
# Sender — bind to the VLAN 2601 interface IP
iperf3.exe -c 239.1.1.1 -u -B 192.168.1.10 -p 5201

# Receiver — bind to the multicast group but join via the correct interface
iperf3.exe -s -B 239.1.1.1%192.168.1.10 -p 5201
```

In the PowerShell UdpClient examples in this guide, bind the socket to the
local endpoint before sending or joining:

```powershell
# Bind to the specific interface IP — overrides routing table for this socket
$localEP = New-Object System.Net.IPEndPoint(
    [System.Net.IPAddress]::Parse("192.168.1.10"), 0)
$udpClient = New-Object System.Net.Sockets.UdpClient($localEP)
```

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

Setting `RouteMetric 1` ensures this route wins over the default route for all
239.x.x.x destinations regardless of interface metric.

Verify the route is in place:

```powershell
Get-NetRoute -DestinationPrefix 239.0.0.0/8
```

To remove the route if no longer needed:

```powershell
Remove-NetRoute -DestinationPrefix 239.0.0.0/8 -InterfaceIndex $ifIndex -Confirm:$false
```

#### Mechanism 3 — Set a High Metric on Competing Default Routes

If non-multicast traffic also needs to exit correctly from each interface,
adjusting metrics is the cleanest long-term solution. Give the multicast
interface a lower metric than any other interface with a default gateway:

```powershell
# Set a high metric on the external interface default route
Set-NetIPInterface -InterfaceIndex (Get-NetAdapter -Name "Ethernet 3").ifIndex `
  -InterfaceMetric 100

# Set a low metric on the VLAN 2601 interface
Set-NetIPInterface -InterfaceIndex (Get-NetAdapter -Name "Ethernet 2").ifIndex `
  -InterfaceMetric 10
```

Note: This affects all traffic routing, not just multicast. Use with care on
machines where specific traffic must exit specific interfaces.

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
traffic appears on Ethernet 3 and not Ethernet 2, the routing table is
selecting the wrong interface. Apply Mechanism 1 or 2 above to correct it.

#### Recommendation for This Environment

For Windows VMs on Proxmox with multiple NICs where one NIC is the designated
multicast interface for a specific VLAN:

```
1. Always use -B <local-ip> in iperf3 to bind to the correct interface.
   This is the most targeted fix and does not affect other traffic.

2. Add a specific 239.0.0.0/8 route for the multicast interface so the
   routing table selection is deterministic regardless of application
   behavior. Use RouteMetric 1 to ensure it wins.

3. Avoid configuring a default gateway on the VLAN data interface
   (Ethernet 2 in the example above). A NIC with no gateway does not
   compete in the default route election and will not accidentally win
   the multicast interface selection through that mechanism.

4. Verify with tshark that IGMP joins are exiting the correct interface
   before concluding the application configuration is correct.
```

---

## 5. Windows Firewall — Multicast Rules

### 5.1 Default Firewall Behavior for Multicast

Windows Firewall blocks inbound UDP traffic by default unless a rule explicitly
permits it. Multicast UDP traffic destined for a 239.x.x.x group address is
subject to the same inbound filtering as unicast UDP. Without an inbound rule,
the Windows network stack will receive the multicast frame at the adapter level
but the firewall will silently drop it before the application socket can read it.

Outbound multicast traffic is permitted by default in Windows Firewall. However,
outbound rules should be explicitly configured for clarity and to prevent
unexpected behavior when the firewall profile changes (e.g. when a machine
moves between domain, private, and public profiles).

Note: Even with the firewall disabled entirely, applications must still join the
multicast group via the socket API for traffic to be delivered. The firewall is
a separate layer from IGMP group membership.

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

Note: Without the IGMP inbound rule, Windows may still send IGMP joins
(because IGMP is processed below the firewall layer in the network stack)
but behavior can vary by Windows version and update level. Explicitly
permitting IGMP is the safe configuration.

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

Test whether a specific port is being blocked by simulating a connection
(useful for unicast verification — multicast requires actual group membership):

```powershell
Test-NetConnection -ComputerName 239.1.1.1 -Port 5001
```

Note: `Test-NetConnection` uses TCP and does not test multicast UDP delivery.
Use iperf3 and Wireshark for actual multicast verification.

### 5.5 Removing Multicast Firewall Rules

Remove a specific rule by display name:

```powershell
Remove-NetFirewallRule -DisplayName "Allow Inbound Multicast UDP 239.x.x.x port 5001"
```

Remove all rules with Multicast in the display name:

```powershell
Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*Multicast*" } |
  Remove-NetFirewallRule
```

---

## 6. Multicast Receiver Configuration

### 6.1 Joining a Multicast Group via PowerShell

Windows does not have a built-in command-line tool equivalent to mcjoin for
persistent group membership without a running application. However PowerShell
can be used to join a group and listen for traffic using the .NET UdpClient
class. This is useful for testing whether the network delivers multicast before
deploying the actual application.

Join a multicast group and listen for UDP packets:

```powershell
# Set the multicast group and port
$group = [System.Net.IPAddress]::Parse("239.1.1.1")
$localEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 5001)

# Create and configure the UDP client
$udpClient = New-Object System.Net.Sockets.UdpClient
$udpClient.Client.SetSocketOption(
    [System.Net.Sockets.SocketOptionLevel]::Socket,
    [System.Net.Sockets.SocketOptionName]::ReuseAddress,
    $true
)
$udpClient.Client.Bind($localEP)

# Join the multicast group
$udpClient.JoinMulticastGroup($group)
Write-Host "Joined multicast group 239.1.1.1 on port 5001. Waiting for packets..."

# Receive packets in a loop (Ctrl+C to stop)
$remoteEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
try {
    while ($true) {
        $bytes = $udpClient.Receive([ref]$remoteEP)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        Write-Host "Received from $($remoteEP.Address):$($remoteEP.Port) — $text"
    }
} finally {
    $udpClient.DropMulticastGroup($group)
    $udpClient.Close()
    Write-Host "Left multicast group."
}
```

Save this as `multicast-receive.ps1` and run with:

```powershell
powershell -ExecutionPolicy Bypass -File multicast-receive.ps1
```

When this script runs, Windows sends an IGMP join for 239.1.1.1. The join
will be visible on the upstream Cisco switch:

```
SWITCH01# show ip igmp snooping groups vlan 2601
```

When the script exits (Ctrl+C), Windows sends an IGMP leave.

### 6.2 Using iperf3 for Windows as a Receiver

iperf3 is the primary recommended tool for multicast testing on Windows. It
handles group joining, IGMP membership, and traffic measurement automatically.

Start iperf3 as a multicast receiver bound to the group address:

```
iperf3.exe -s -B 239.1.1.1 -p 5201
```

Parameters:

```
-s            Server mode (receiver)
-B 239.1.1.1  Bind to the multicast group address — triggers IGMP join
-p 5201       UDP port to listen on
```

iperf3 will join the multicast group automatically when bound to a multicast
address. The IGMP join will be visible in Wireshark and on the switch snooping
table.

To specify the local interface explicitly (recommended when the Windows VM has
multiple NICs):

```
iperf3.exe -s -B 239.1.1.1 -p 5201 --bind-dev "Ethernet 2"
```

Note: The `--bind-dev` flag may not be available in all iperf3 Windows builds.
If unavailable, use `-B <local-ip>` to bind to the specific interface IP:

```
iperf3.exe -s -B 239.1.1.1%192.168.1.10 -p 5201
```

The `%192.168.1.10` suffix tells iperf3 to use the interface with that local
IP address for the multicast join.

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
receive it, the firewall is the likely cause. See section 5.

---

## 7. Multicast Sender Configuration

### 7.1 Using iperf3 for Windows as a Sender

iperf3 in client mode sends multicast UDP traffic to a specified group address.
A receiver (iperf3 server) must be running and listening on the group and port
before the sender starts.

Send multicast UDP to a group:

```
iperf3.exe -c 239.1.1.1 -u -b 1M -p 5201 --time 30
```

Parameters:

```
-c 239.1.1.1   Send to the multicast group address
-u             UDP mode (required for multicast)
-b 1M          Target bandwidth of 1 Mbit/s
-p 5201        Destination port matching the receiver
--time 30      Run for 30 seconds
```

Specify the source interface by binding to the local IP:

```
iperf3.exe -c 239.1.1.1 -u -b 1M -p 5201 -B 192.168.1.10 --time 30
```

Set the multicast TTL (Time To Live). A TTL of 1 limits the traffic to the
local subnet, which is correct for intra-VLAN multicast:

```
iperf3.exe -c 239.1.1.1 -u -b 1M -p 5201 --multicast-ttl 1 --time 30
```

The sender does not join the multicast group. Only receivers send IGMP joins.
The sender simply transmits UDP packets to the multicast destination address.

### 7.2 Sending Multicast via PowerShell

A PowerShell script can send multicast UDP packets to a group without requiring
iperf3. This is useful for testing when iperf3 is not available.

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
powershell -ExecutionPolicy Bypass -File multicast-send.ps1
```

---

## 8. Required Tools and Installation

### 8.1 iperf3 for Windows

iperf3 does not have an official Windows installer. Use the builds maintained
by the iperf3 community or install via winget.

Install via winget (Windows 11 and Server 2022 with winget available):

```powershell
winget install -e --id iperf3.iperf3
```

Manual installation if winget is not available:

```powershell
# Download iperf3 for Windows (64-bit)
$url = "https://github.com/ar51an/iperf3-win-builds/releases/latest/download/iperf3.exe"
$dest = "C:\Tools\iperf3.exe"

New-Item -ItemType Directory -Force -Path "C:\Tools" | Out-Null
Invoke-WebRequest -Uri $url -OutFile $dest

# Add to PATH for the current session
$env:PATH += ";C:\Tools"

# Add to PATH permanently (requires admin)
[System.Environment]::SetEnvironmentVariable(
    "PATH",
    [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";C:\Tools",
    "Machine"
)
```

Verify installation:

```powershell
iperf3.exe -v
```

Note: The download URL above references a community build repository. Verify
the URL is current and the binary is from a trusted source before deploying
in a production environment.

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

Show active UDP listeners (verifies iperf3 or application is listening):

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

Show the routing table (verify there is a multicast route):

```powershell
Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -like "239*" }
```

Windows automatically adds a route for 239.0.0.0/8 when an interface has an
IP address assigned. If this route is missing, add it manually:

```powershell
New-NetRoute -DestinationPrefix 239.0.0.0/8 -InterfaceIndex $ifIndex -NextHop 0.0.0.0
```

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

This scenario tests multicast delivery from a Windows VM on PVE04 VLAN 2601
to a physical client connected to SWITCH02 Gi1/0/1, also on VLAN 2601.

Environment:

```
Sender:   Windows VM on PVE04, VLAN 2601, IP 192.168.1.10, adapter "Ethernet 2"
Receiver: Physical client on SWITCH02 Gi1/0/1, VLAN 2601, IP 192.168.1.20
Group:    239.1.1.1, UDP port 5201
```

**Step 1 — Verify bridge configuration on PVE04**

On PVE04 (Proxmox host):

```bash
cat /sys/class/net/vmbr999/bridge/multicast_snooping
```

Expected: `0`

**Step 2 — Verify IGMP snooping querier on SWITCH01**

On SWITCH01:

```
show ip igmp snooping querier vlan 2601 detail
```

Confirm the querier address is `10.32.204.254` and status is active.

**Step 3 — Add Windows Firewall rules on the Windows VM**

On the Windows VM (elevated PowerShell):

```powershell
New-NetFirewallRule `
  -DisplayName "Allow Inbound Multicast UDP 239.x.x.x port 5201" `
  -Direction Inbound -Protocol UDP `
  -LocalAddress 239.0.0.0/8 -LocalPort 5201 `
  -Action Allow -Profile Any -Enabled True

New-NetFirewallRule `
  -DisplayName "Allow Outbound Multicast UDP 239.x.x.x port 5201" `
  -Direction Outbound -Protocol UDP `
  -RemoteAddress 239.0.0.0/8 -RemotePort 5201 `
  -Action Allow -Profile Any -Enabled True

New-NetFirewallRule `
  -DisplayName "Allow Inbound IGMP" `
  -Direction Inbound -Protocol 2 `
  -Action Allow -Profile Any -Enabled True

New-NetFirewallRule `
  -DisplayName "Allow Outbound IGMP" `
  -Direction Outbound -Protocol 2 `
  -Action Allow -Profile Any -Enabled True
```

**Step 4 — Start the receiver on the physical client**

On the physical client (Linux or Windows with iperf3):

```bash
# Linux physical client
iperf3 -s -B 239.1.1.1 -p 5201
```

Or on a Windows physical client:

```
iperf3.exe -s -B 239.1.1.1 -p 5201
```

Leave this running.

**Step 5 — Verify the IGMP join reached SWITCH01 and SWITCH02**

On SWITCH01:

```
show ip igmp snooping groups vlan 2601
```

The physical client's port (arriving via SWITCH02 trunk) should appear as a
member of group 239.1.1.1.

On SWITCH02:

```
show ip igmp snooping groups vlan 2601
```

The physical client's port (Gi1/0/1) should appear as a member of 239.1.1.1.

**Step 6 — Start the sender on the Windows VM**

On the Windows VM:

```
iperf3.exe -c 239.1.1.1 -u -b 1M -p 5201 -B 192.168.1.10 --multicast-ttl 1 --time 30
```

**Step 7 — Verify traffic is leaving the Windows VM**

In a second PowerShell window on the Windows VM, capture with tshark:

```powershell
tshark -i "Ethernet 2" -f "host 239.1.1.1" -n
```

You should see outbound UDP packets destined for 239.1.1.1.

**Step 8 — Verify traffic is crossing the bond on PVE04**

On PVE04:

```bash
sudo tcpdump -i bond999 -nn 'vlan 2601 and host 239.1.1.1'
```

You should see multicast frames tagged with VLAN 2601 traversing the bond.

**Step 9 — Verify receipt at the physical client**

The iperf3 server on the physical client should report received traffic in
its output, showing bitrate, packet loss, and jitter.

**Expected successful flow:**

```
Windows VM sends UDP to 239.1.1.1
    ↓ tap interface (multicast frame exits VM via Proxmox bridge)
    ↓ vmbr999 (bridge-mcsnooping 0, transparent forwarding)
    ↓ bond999 (LACP bond delivers to SWITCH01 Po4)
    ↓ SWITCH01 (IGMP snooping forwards to SWITCH02 trunk)
    ↓ SWITCH02 (IGMP snooping forwards to Gi1/0/1)
    ↓ Physical client receives multicast packet
```

---

## 10. Troubleshooting

### 10.1 Multicast Not Leaving the Windows VM

Symptom: tshark on the Windows VM shows no outbound multicast traffic when
iperf3 or the PowerShell sender is running.

Step 1 — Verify the interface has an IP address:

```powershell
Get-NetIPAddress -AddressFamily IPv4 | Select InterfaceAlias, IPAddress
```

Without a source IP, Windows will not send multicast frames.

Step 2 — Verify the multicast route exists:

```powershell
Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -like "239*" }
```

If missing, add the route:

```powershell
New-NetRoute -DestinationPrefix 239.0.0.0/8 -InterfaceIndex $ifIndex -NextHop 0.0.0.0
```

Step 3 — Verify the application is binding to the correct interface. If the
Windows VM has multiple NICs, the application may be sending via the wrong one.
Use the `-B <local-ip>` flag in iperf3 to bind to the specific interface IP.

Step 4 — Verify outbound firewall rules are not blocking multicast UDP:

```powershell
Get-NetFirewallRule | Where-Object {
  $_.Direction -eq "Outbound" -and $_.Enabled -eq "True" -and $_.Action -eq "Block"
} | Select DisplayName
```

### 10.2 Multicast Not Arriving at the Windows VM

Symptom: tshark on the Windows VM shows multicast frames arriving (visible in
the raw capture) but the iperf3 server or PowerShell receiver reports nothing.

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

Step 3 — Temporarily disable the Windows Firewall to isolate it as the cause:

```powershell
Set-NetFirewallProfile -All -Enabled False
```

If multicast starts arriving, the firewall is the cause. Re-enable and add the
correct rules:

```powershell
Set-NetFirewallProfile -All -Enabled True
```

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

You should see an IGMP membership report for 239.1.1.1. If no IGMP traffic
appears, the Windows stack is not sending the join. Verify the application
has successfully called the socket join API (no error from iperf3 or the
PowerShell script).

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

This is caused by IGMP membership timeout. The switch querier is sending
general queries, but the Windows VM is either not receiving them or not
responding with membership reports.

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

Step 3 — Verify the application is still running. Windows IGMP membership is
application-driven. If the application exits or crashes, the group is left
immediately and the switch removes the membership entry.

```powershell
Get-Process -Name iperf3 -ErrorAction SilentlyContinue
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

Step 2 — Check for conflicting block rules with higher priority:

```powershell
Get-NetFirewallRule | Where-Object {
  $_.Action -eq "Block" -and $_.Direction -eq "Inbound" -and $_.Enabled -eq "True"
} | Select DisplayName, Profile | Format-Table -AutoSize
```

Block rules take precedence over allow rules in Windows Firewall when they are
more specific. A block rule for all UDP inbound will override an allow rule for
multicast UDP.

Step 3 — Check for domain GPO overrides:

```powershell
gpresult /r /scope computer | Select-String -Pattern "Firewall"
```

If Group Policy is managing the firewall, local rules may be ignored entirely.
Contact the domain administrator to have the multicast rules added at the GPO
level.

Step 4 — Enable Windows Firewall audit logging to capture blocked traffic:

```powershell
Set-NetFirewallProfile -All -LogBlocked True -LogFileName "C:\Windows\System32\LogFiles\Firewall\pfirewall.log"
```

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
| IGMPv3                | IGMP version 3. Default on modern Windows. Supports source-specific multicast.  |
| iperf3                | Network performance testing tool with multicast UDP support.                    |
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
| vmbr999               | VLAN-aware Linux bridge on PVE hosts. bridge-mcsnooping 0 for transparency.     |
| Wireshark             | GUI packet capture and analysis tool.                                           |
| Windows Firewall      | Built-in stateful firewall in Windows. Filters inbound and outbound traffic.    |
| winget                | Windows Package Manager. Used to install iperf3 and Wireshark.                  |
| 239.0.0.0/8           | Administratively scoped multicast range. Private use, not internet-routable.    |
