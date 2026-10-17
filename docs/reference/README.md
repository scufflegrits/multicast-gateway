# Platform reference guides

**Coverage: IPv4 multicast only.** IPv6/MLD procedures are outside these guides.
mcgw's own IPv4/IPv6 scope remains defined in [architecture](../architecture.md).

## Contents

- [Guide index](#guide-index)
- [How to use these guides](#how-to-use-these-guides)
- [Appendix A — Acronyms and meanings](#appendix-a--acronyms-and-meanings)
- [Appendix B — Verification sources](#appendix-b--verification-sources)

## Guide index

| Guide | Intended context | Qualification limit |
|---|---|---|
| [Cisco](MulticastReference-Cisco_r1.0.0.md) | Catalyst 9200/9300; L2 snooping/querier and related troubleshooting | Not C8570-G2/9400 certification; verify exact IOS XE image |
| [Debian / Proxmox](MulticastReference-LinuxDebian_r1.0.3.md) | Debian 13 guests, Linux bridges and multicast tools | Validate installed Proxmox/ifupdown2, guest kernel and test-tool versions |
| [RHEL / VMware](MulticastReference-LinuxRHEL9-10_r1.0.0.md) | RHEL 9/10 bare metal or vSphere guests | Validate exact RHEL repositories, SELinux/firewall policy and vSphere 9 build |
| [Windows](MulticastReference-Windows_r1.0.1.md) | Windows Server 2022 / Windows 11; PowerShell socket tests and optional iperf2 | Qualify actual OS/.NET/tool builds; iperf3 is not a multicast test tool |

## How to use these guides

| Rule | Meaning |
|---|---|
| Source of mcgw requirements | [Architecture](../architecture.md), not an illustrative platform configuration |
| Evidence levels | Each source appendix separates documented mechanisms from untested commands/topologies |
| Lab values | Hostnames, VLANs, addresses, bonds and bridge names are examples, not prerequisites |
| Inspection versus changes | Read the command-use table; configuration/route/firewall/service operations change state |
| Socket tests | Group joins and senders create membership/traffic; explicitly select interface and bound test rate/window |
| Flooding | Disabling snooping is a deliberate bandwidth/isolation tradeoff, not a general fix |
| Maintenance | Filenames retained for stable links; review dates in history identify the update |
| Checks | Run `python3 scripts/check-docs.py` from the repository root; it includes these guides |

## Appendix A — Acronyms and meanings

| Term | Meaning |
|---|---|
| IPv4 | Internet Protocol version 4 |
| IPv6 | Internet Protocol version 6; outside reference-guide coverage |
| IGMP | Internet Group Management Protocol |
| MLD | Multicast Listener Discovery; outside reference-guide coverage |
| L2 | Layer 2 — link-layer switching |
| RHEL | Red Hat Enterprise Linux |
| VLAN | Virtual Local Area Network |
| OS | Operating System |
| VM | Virtual Machine |

## Appendix B — Verification sources

This index introduces no independent platform behavior. Verification sources,
access dates, scope and remaining test requirements are in each guide:

- [Cisco source appendix](MulticastReference-Cisco_r1.0.0.md#appendix-b--verification-sources)
- [Debian source appendix](MulticastReference-LinuxDebian_r1.0.3.md#appendix-b--verification-sources)
- [RHEL source appendix](MulticastReference-LinuxRHEL9-10_r1.0.0.md#appendix-b--verification-sources)
- [Windows source appendix](MulticastReference-Windows_r1.0.1.md#appendix-b--verification-sources)
