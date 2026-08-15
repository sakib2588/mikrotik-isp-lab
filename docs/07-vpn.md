# WireGuard site-to-site VPN --- CHR-PE to CHR-CPE

## Why

Named directly by the Fame IT Networks posting ("VPN" in the required list) and independently
flagged three times, including an external CV review --- see `CV/Nazmus_Sakib_CV_NOC.md`.

## Design decision: tunnel rides the access link, not the admin network

The first attempt addressed the WireGuard peers over `192.168.56.0/24`, the host-only
management subnet. That is wrong for two reasons: it is not how a real ISP would deploy a
site-to-site VPN to a customer edge, and CHR-CPE only has a management IP on that subnet
temporarily (see `docs/02-build-notes.md`, "CHR-CPE ether3 was a temporary management path").
Once that adapter is removed, an endpoint pinned to `192.168.56.11` would be permanently
unreachable and the tunnel would silently die.

The corrected design tunnels over the PPPoE session between CHR-PE and CHR-CPE --- the same
access link a real broadband subscriber uses --- which is present for as long as the customer
is online, with no dependency on the temporary admin adapter:

| Router | WireGuard listens on | Peer endpoint |
|---|---|---|
| CHR-PE | `wg-to-cpe`, port 13231 | CPE's live PPPoE session address, `100.64.0.52` (CGNAT pool, changes per session) |
| CHR-CPE | `wg-to-pe`, port 13231 | PE's PPPoE-server-side address, `10.20.0.1` (stable) |

**Honest limitation:** the CPE-side endpoint address is the dynamically assigned PPPoE session
address, which changes on reconnect. A production deployment would either use a DNS name with
dynamic DNS on the customer side, or accept the small window where the tunnel needs a manual
endpoint refresh after a session bounce. Documented here rather than glossed over, the same
convention already used in `docs/05-gpon-olt-notes.md` for the GPON/OLT gap.

## Addressing

Tunnel subnet `172.16.1.0/30` --- checked against every subnet already in use in this lab
(`192.168.56.0/24`, `10.0.2.0/24`, `10.99.0.0/30`, `10.255.0.0/30`, `10.255.255.0/24`,
`172.16.0.0/30`, `192.168.88.0/24`, `198.51.100.0/24`, `192.0.2.0/24`, `203.0.113.0/24`) to
avoid a collision with the existing `172.16.0.0/30` link between CHR-CORE and CHR-UPSTREAM.

| Router | Tunnel address |
|---|---|
| CHR-PE (`wg-to-cpe`) | `172.16.1.1/30` |
| CHR-CPE (`wg-to-pe`) | `172.16.1.2/30` |

## Build

```
# on CHR-PE
/interface wireguard add name=wg-to-cpe listen-port=13231
/ip address add address=172.16.1.1/30 interface=wg-to-cpe network=172.16.1.0
/interface wireguard peers add interface=wg-to-cpe public-key="<CPE public key>" \
    allowed-address=172.16.1.2/32 endpoint-address=100.64.0.52 endpoint-port=13231 \
    persistent-keepalive=25s

# on CHR-CPE
/interface wireguard add name=wg-to-pe listen-port=13231
/ip address add address=172.16.1.2/30 interface=wg-to-pe network=172.16.1.0
/interface wireguard peers add interface=wg-to-pe public-key="<PE public key>" \
    allowed-address=172.16.1.1/32 endpoint-address=10.20.0.1 endpoint-port=13231 \
    persistent-keepalive=25s
```

No firewall changes were needed on either side. CHR-PE's input chain only drops traffic
arriving on `ether1` (the internet-facing WAN); the PPPoE/access side has no equivalent drop
rule, so the WireGuard handshake reaches the router unblocked. CHR-CPE has no filter rules at
all beyond NAT masquerade for the customer LAN.

## Verification

Ping across the tunnel addresses, both directions, 0% loss:

```
[admin@CHR-CPE] > /ping 172.16.1.1 count=4
  sent=4 received=4 packet-loss=0% min-rtt=349us avg-rtt=391us max-rtt=461us
```

Peer state on CHR-PE confirms a live, recent handshake with non-zero counters --- not just a
configured peer that has never actually spoken:

```
[admin@CHR-PE] > /interface wireguard peers print detail
 0    interface=wg-to-cpe name="peer2"
      endpoint-address=100.64.0.52 endpoint-port=13231
      current-endpoint-address=100.64.0.52 current-endpoint-port=13231
      allowed-address=172.16.1.2/32 persistent-keepalive=25s
      rx=564 tx=656
      last-handshake=33s
```

## Proof of encryption --- the interview artifact

Two captures were taken with `/tool sniffer` while pinging across the tunnel from CHR-CPE,
one below WireGuard (on `ether3`, the physical wire) and one above it (on the `wg-to-cpe`
interface itself, after decryption). Same six pings, two vantage points:

**`captures/wg-encrypted-wire.pcap` --- on the wire, before decryption.** Every packet is an
opaque UDP datagram on port 13231. The five-tuple, sequence numbers and ICMP payload are not
visible --- this is what someone tapping the access line actually sees:

```
16:16:34.920818 PPPoE [ses 0x3] IP 100.64.0.52.13231 > 10.20.0.1.13231: UDP, length 96
16:16:34.921006 PPPoE [ses 0x3] IP 10.20.0.1.13231 > 100.64.0.52.13231: UDP, length 96
```

**`captures/wg-decrypted-tunnel.pcap` --- same traffic, captured on `wg-to-cpe` after
decryption.** The identical ping now reads as plaintext ICMP, because this vantage point is
inside the router's own IP stack, past the point WireGuard peels the encryption off:

```
16:16:43.438580 IP 172.16.1.2 > 172.16.1.1: ICMP echo request, id 769, seq 1536, length 36
16:16:43.438600 IP 172.16.1.1 > 172.16.1.2: ICMP echo reply, id 769, seq 1536, length 36
```

Same six round trips, two files, two completely different readabilities. That contrast --- not
the green ping output --- is the actual proof the tunnel is doing something, and it is the
answer to "walk me through this capture" for VPN specifically.

## What this does not cover

- No rekey/reconnect test --- WireGuard's automatic key rotation was not deliberately
  exercised or captured.
- IRR/route-based failover is out of scope for a point-to-point VPN between two routers already
  connected by PPPoE; this tunnel demonstrates the mechanism, not a redundancy design.
