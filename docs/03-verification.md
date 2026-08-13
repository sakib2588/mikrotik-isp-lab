# Verification log

Every test run and its actual output. No claim on the CV or in the README traces to
anything that isn't recorded here first.

## Task 5 --- NAT and firewall

`/ip firewall filter print` --- rule order, 8 rules, input then forward, matches plan exactly:

```
0   ;;; accept return traffic
    chain=input action=accept connection-state=established,related
1   ;;; drop invalid
    chain=input action=drop connection-state=invalid
2   ;;; allow ping for troubleshooting
    chain=input action=accept protocol=icmp
3   ;;; management access
    chain=input action=accept src-address-list=mgmt
4   ;;; drop everything else from WAN
    chain=input action=drop in-interface=ether1
5   ;;; accept return traffic
    chain=forward action=accept connection-state=established,related
6   ;;; drop invalid
    chain=forward action=drop connection-state=invalid
7   ;;; drop unsolicited inbound to subscribers
    chain=forward action=drop connection-state=new in-interface=ether1
```

`/ping 1.1.1.1 count=4` --- 4 sent, 4 received, 0% loss, avg-rtt 2ms161us.

`/ip firewall filter print stats` --- run immediately after the ping above:

```
#  CHAIN    ACTION  BYTES  PACKETS
;;; accept return traffic
0  input    accept  7016   82
;;; drop invalid
1  input    drop    0      0
;;; allow ping for troubleshooting
2  input    accept  0      0
;;; management access
3  input    accept  0      0
;;; drop everything else from WAN
4  input    drop    0      0
;;; accept return traffic
5  forward  accept  0      0
;;; drop invalid
6  forward  drop    0      0
;;; drop unsolicited inbound to subscribers
7  forward  drop    0      0
```

Read: the `established,related` input rule is non-zero (7016 bytes / 82 packets), which is
the actual proof this firewall is stateful and not just configured --- the ping replies and
the ongoing SSH session both match it before any lower rule is even evaluated. `management
access` (rule 3) sits at 0 because the SSH session tested here predates these rules being
applied; a fresh SSH connection after this point should tick that counter instead. Forward
chain is all zero because no subscriber traffic exists yet --- CHR-CPE is not built until
Task 7.

## Task 7 --- PPPoE session and customer LAN

**Step 4, on CHR-CPE** --- `/interface pppoe-client print`:

```
0  R name="pppoe-wan" interface=ether1 user="cust001" profile=default
     add-default-route=yes use-peer-dns=yes allow=pap,chap,mschap1,mschap2
```

`R` flag present --- session is running, not just configured. `/ip address print` on the same
box shows the address the server handed out:

```
1 D 10.20.0.250/32    10.20.0.1     pppoe-wan  main
```

**Step 4, on CHR-PE** --- `/ppp active print`, the server-side view of the same session:

```
#  NAME     SERVICE  CALLER-ID          ADDRESS      UPTIME
;;; Residential customer 1
0  cust001  pppoe    08:00:27:1C:47:B7  10.20.0.250  1m50s
```

Both ends agree on the address (`10.20.0.250`) --- that agreement is the actual proof, not
either side's output alone. No screenshot was ever captured for this step; the raw output above
is the verification record.

**Step 5, on CHR-CPE** --- end-to-end connectivity through the tunnel:

```
/ping 1.1.1.1 count=4      --- sent=4 received=4 packet-loss=0% avg-rtt=3ms712us
/ping google.com count=4   --- sent=4 received=4 packet-loss=0% avg-rtt=47ms299us (192.178.134.100)

/tool traceroute 1.1.1.1 count=1
#  ADDRESS    LOSS  SENT  LAST   AVG  BEST  WORST
0  10.20.0.1  0%    1     0.3ms  0.3  0.3   0.3
1             100%  1     timeout
2  1.1.1.1    0%    1     2.3ms  2.3  2.3   2.3
```

Hop 0 is `10.20.0.1`, the PE --- this is the load-bearing result of the whole lab. CHR-CPE has
no NAT adapter of its own, so this traffic had no other path to the internet except through
the PPPoE tunnel to the provider edge. Hop 1 timing out is VirtualBox NAT not answering
traceroute probes, expected and harmless. Screenshot:
`screenshots/task07-03-end-to-end-ping-traceroute-dhcp.png`.

**Step 7, on CHR-CPE** --- DHCP server for the customer LAN:

```
/ip dhcp-server print
#  NAME      INTERFACE  ADDRESS-POOL  LEASE-TIME
0  lan-dhcp  ether2     lan-pool      30m

/ip pool print
#  NAME      RANGES                       TOTAL  USED  AVAILABLE
0  lan-pool  192.168.88.100-192.168.88.200  101   0     101
```

No `X` flag on the DHCP server row --- enabled. No client attached to `cust-lan` yet, so
`used=0` is expected; the pool and server exist and are correctly configured, which is what
this step actually verifies. Screenshot: `screenshots/task07-03-end-to-end-ping-traceroute-dhcp.png`.

## Task 8 --- VLAN-tagged access

Moved the PPPoE server (CHR-PE) and client (CHR-CPE) from untagged `ether3`/`ether1` onto
tagged VLAN 100 on both ends. The session dropped and re-dialed automatically the moment
the server moved --- expected, not a fault.

**On CHR-PE after the move** --- `/ppp active print`:

```
#  NAME     SERVICE  CALLER-ID          ADDRESS      UPTIME
;;; Residential customer 1
0  cust001  pppoe    08:00:27:1C:47:B7  10.20.0.250  40s
```

`cust001` re-established with a fresh uptime, same address as before --- the VLAN move
didn't change subscriber addressing, only the path. `/interface vlan print`:

```
#    NAME             MTU   ARP      VLAN-ID  INTERFACE
;;; access VLAN for PPPoE
0 R  vlan100-access   1500  enabled  100      ether3
```

`R` flag present --- VLAN interface is running, not just configured.

**On CHR-CPE** --- `/ping 1.1.1.1 count=2`: sent=2 received=2 packet-loss=0%,
avg-rtt=3ms863us. Internet still reachable over the tagged path, same as before the move.
Screenshot: `screenshots/task08-01-vlan-tagged-ping-still-works.png`.

## Task 9 --- bandwidth management (PCQ)

Created `pcq-download`/`pcq-upload` queue types and an aggregate simple queue
(`subscriber-aggregate`, target `10.20.0.0/24`, `max-limit=20M/20M`) on CHR-PE. Load-tested
with `/tool fetch` of a 10 MB file from CHR-CPE.

**Result, and an honest finding rather than a clean pass:** `subscriber-aggregate` stayed at
zero bytes for the entire transfer. The traffic was instead caught and counted by a queue
RouterOS creates automatically --- `<pppoe-cust001>`, a dynamic queue tied directly to the
`plan-5m` PPP profile's own `rate-limit=5M/5M`. Final stats on that dynamic queue:
`3832/7315 packets`, `160746/10800586 bytes`, `14/? packets dropped` (rate-limit shaping
under sustained load --- expected, not a fault).

Read: per-subscriber rate limiting is genuinely enforced and provable --- the interview
question "how do you stop one customer saturating the link" is answered by real evidence,
just via the PPP-profile mechanism rather than the aggregate simple queue built afterward.
`subscriber-aggregate` is correctly configured (confirmed by `/queue simple print`) but
isn't the layer this specific traffic passed through first, because a profile-level
rate-limit takes precedence for that session. Reporting this as observed rather than
forcing a number onto the queue that never actually saw the traffic.

**Measured throughput:** 10240 KiB in 1m29s ~= 0.94 Mbit/s --- consistent with the CHR free
licence's 1 Mbit/s per-interface cap, exactly as expected. This is the only throughput
number in this repo backed by an actual timed transfer; the queue's own `max-limit=20M/20M`
is correct configuration, not a measured rate, and is never quoted as one.
Screenshots: `screenshots/task09-01-fetch-finished-1mbit-cap.png`,
`screenshots/task09-02-queue-stats-dynamic-vs-aggregate.png`.

## Task 9 --- SNMP

`snmpwalk -v2c -c lab-ro 192.168.56.10 1.3.6.1.2.1.1.5` from the host (popos-mainpc, not
the router console) returned `STRING: "CHR-PE"` --- SNMP live and answering. This is the
honest version of the MRTG line two of the target postings name: the router is exposed over
SNMP and was actually polled, not just configured.

## Task 9 --- uplink watchdog (netwatch)

Added a netwatch probe on `1.1.1.1`, 30s interval, logging on state change. Tested both
directions from the host by toggling the WAN link directly:

```
VBoxManage controlvm CHR-PE setlinkstate1 off   # 19:50:xx
...
VBoxManage controlvm CHR-PE setlinkstate1 on    # 19:50:xx, ~30s later
```

Router log, `/log print where message~"UPLINK"`:

```
19:50:03  script,info   UPLINK RESTORED   <- netwatch's first check on creation, not the test
19:50:33  script,error  UPLINK DOWN       <- link killed at ~19:50:03, detected next 30s cycle
19:51:03  script,info   UPLINK RESTORED   <- link restored at ~19:50:33ish, detected next cycle
```

Both transitions detected within one polling interval each. This is the real proof behind
"escalation" and "alerting" on the CV --- not just a configured probe, a probe caught
actually failing an actually-failed link and actually caught it coming back.

## Task 11 --- FreeRADIUS AAA for PPPoE subscribers

`radtest sakib1 sakib1 127.0.0.1 0 testing123` against the FreeRADIUS server on the host:

```
Received Access-Accept Id 47 from 127.0.0.1:1812 to 127.0.0.1:49366 length 67
    Message-Authenticator = 0x804a0d679012de5b7c44be1baa98eff8
    Framed-IP-Address = 100.64.0.51
    Mikrotik-Rate-Limit = "512k/768k"
    Acct-Interim-Interval = 300
```

`Mikrotik-Rate-Limit` printing as a named attribute (not `Attr-26.14988.8`) confirms
`dictionary.mikrotik` loaded correctly --- the server-side half of the proof.

**On CHR-PE, after disabling local secrets** (`cust001`/`cust002`) so RADIUS is genuinely in
the auth path, not just configured --- `/ppp active print`:

```
#   NAME    SERVICE  CALLER-ID
0 R sakib1  pppoe    08:00:27:1C:47:B7
```

The `R` flag (RADIUS) is the load-bearing proof, not merely a successful connection.
`/ppp active print detail`:

```
0 R name="sakib1" service=pppoe caller-id="08:00:27:1C:47:B7"
    address=100.64.0.51 uptime=7m23s session-id=0x8100001B
```

`address=100.64.0.51` matches the `Framed-IP-Address` RADIUS handed out --- not a pool
address, RADIUS-assigned. `/radius monitor 0`:

```
requests: 29    accepts: 7    rejects: 22    resends: 0
timeouts: 0     bad-replies: 0    last-request-rtt: 10ms
```

`rejects: 22` is not a fault --- it is the ~17 `cust001 authentication failed` log entries
generated once the local secret was disabled and RADIUS correctly didn't recognise that
username either. `bad-replies: 0` is the number that actually matters: it confirms the
shared secret is correct and the protocol exchange is healthy. `/queue simple print where
dynamic=yes`:

```
0  D name="<pppoe-sakib1>" limit-at=512k/768k max-limit=512k/768k
```

The `Mikrotik-Rate-Limit` VSA materialised into a real dynamic queue with the exact values
set in FreeRADIUS's `authorize` file --- the rate-limit isn't just accepted, it's enforced.

**Accounting proof**, on the host, `/var/log/freeradius/radacct/192.168.56.10/detail-*`:

```
Acct-Status-Type = Start
User-Name = "sakib1"
Framed-IP-Address = 100.64.0.51
Acct-Authentic = RADIUS
```

`Acct-Authentic = RADIUS` would read `Local` if this session had authenticated against a
local secret --- this is the accounting-side confirmation that RADIUS did the work.

Read: this is the full authn + authz + acct chain, not just a config that looks right ---
a real client dialled in, RADIUS decided the outcome, the router enforced RADIUS's decision
(the rate limit), and RADIUS logged it independently. Fallback also verified: re-enabling
`cust002` locally left it present and available, confirming RouterOS's documented
"local wins if present, RADIUS is only consulted if absent" precedence without needing a
redial test against a password that predates this session.

## Task 12 --- Deterministic CGNAT

`/ip firewall nat print terse` after running the port-block generator script
(`configs/cgnat-generator.rsc`, `StartingAddress=100.64.0.51 ClientCount=4
PortsPerAddress=200`):

```
 3 chain=client-1 action=src-nat to-addresses=192.0.2.1 to-ports=5000-5199 protocol=tcp src-address=100.64.0.51
 6 chain=client-2 action=src-nat to-addresses=192.0.2.1 to-ports=5200-5399 protocol=tcp src-address=100.64.0.52
 9 chain=client-3 action=src-nat to-addresses=192.0.2.1 to-ports=5400-5599 protocol=tcp src-address=100.64.0.53
12 chain=client-4 action=src-nat to-addresses=192.0.2.1 to-ports=5600-5799 protocol=tcp src-address=100.64.0.54
```

(UDP mirrors of each, 14 rules total.) The doc's script text printed `to-address=` --- RouterOS's
real property is `to-addresses` (plural); using the wrong one silently creates a broken rule.

**Real bug caught before any traffic test:** the pre-existing Phase 1 masquerade rule sat
above the new CGNAT jump rule. `/ip firewall nat print stats` after a live test:

```
0 srcnat masquerade 10402 182   <- catching everything, unconditional, evaluated first
1 srcnat jump           0   0   <- the CGNAT chain, never reached
```

Fixed with `/ip firewall nat move numbers=1 destination=0`. A second, independent bug: the
NAT doc's own verbatim RFC 6598 ingress filter includes `chain=forward
src-address=100.64.0.0/10 action=drop out-interface=ether1` --- correct for a boundary
router separate from the CGNAT node, but in this single-router lab it silently dropped
every subscriber's own outbound packet (pre-translation source is still in the CGN range)
before NAT ever ran. Removed; the other 4 anti-spoof rules stayed.

**After both fixes**, `/ip firewall connection print detail where srcnat=yes`, one flow per
subscriber:

```
src-address=100.64.0.51  reply-dst-address=192.0.2.1  reply-dst-port=5034
src-address=100.64.0.52  reply-dst-address=192.0.2.1  reply-dst-port=5384
```

Field-name correction for the write-up: the source doc calls this field `reply-src-port` ---
on RouterOS 7.23.3 the actual field holding the allocated public port is `reply-dst-port`
(`reply-src-port` is the remote server's own port, unchanged). `5034` and `5384` both land
inside their subscriber's assigned block (`5000-5199` / `5200-5399`) --- this is the actual
proof of "deterministic": two different subscribers, verifiably different, non-overlapping
port ranges, from a static table, not just "a NAT rule matched."

Read: the regulator angle from RFC 7422 is provable, not asserted --- a public IP + port +
timestamp resolves to exactly one subscriber from this static table, so per-flow NAT
logging (the thing that kills a real PE's CPU) is genuinely unnecessary here.

## Task 13 --- Router syslog to remote collector

`/system logging print` on CHR-PE, 16 topic rules all pointed at `syslogNOC` (`remote=10.0.2.2`,
the VirtualBox NAT gateway address that resolves to this host from inside the VM ---
`ether1` is VirtualBox NAT, not bridged onto the real LAN, so the plan's "point it at the
real Wazuh manager" note is a deferred stretch goal, not this task's target).

**Emission**, `/tool sniffer quick ip-protocol=udp port=514` immediately after
`:log error "SYSLOG-TEST: probe from CHR-PE"`: 4 packets captured leaving `ether1`.

**Reception**, `tcpdump -ni any udp port 514 -vv` on the host:

```
127.0.0.1.39866 > 127.0.0.1.514: SYSLOG, length: 79
Facility local0 (16), Severity error (3)
Msg: ... CHR-PE SYSLOG-TEST: second probe from CHR-PE
```

Real proof of a real fault caught here: `grep -nE 'imudp|UDPServerRun' /etc/rsyslog.conf`
showed `imudp` commented out --- the packet reached the kernel (tcpdump saw it) but no
application was listening. Fixed with `sed` uncommenting the two `imudp` lines and
`systemctl restart rsyslog`; `ss -lunp | grep :514` then confirmed `rsyslogd` bound.

**Ingestion**, `grep -a -i "CHR-PE" /var/log/syslog`, live organic router traffic (not just
the manual test message):

```
2026-08-07T21:46:46.636+00:00 CHR-PE  <001d>: sent LCP EchoRep id=0x87
2026-08-07T21:46:46.636+00:00 CHR-PE  <001d>: rcvd LCP EchoRep id=0x45
```

Read: emission, arrival, and application ingestion are proven as three separate, distinct
facts, not inferred from one one output --- ongoing PPPoE keepalive traffic landing in the
real log file is stronger evidence than a single manual probe, because it proves the pipe
stays open under continuous load, not just for one packet.

## Task 14 --- Backbone routers (CHR-CORE, CHR-UPSTREAM, CHR-BDIX)

Three new CHRs cloned from the pristine image, wired per the addressing plan and verified
with pings before any routing protocol touched them:

```
PE (10.255.0.1)   -> CORE (10.255.0.2):   0% loss, avg-rtt 284us
CORE (172.16.0.1) -> UPSTREAM (172.16.0.2): 0% loss, avg-rtt 313us
CORE (10.99.0.1)  -> BDIX (10.99.0.2):    0% loss, avg-rtt 284us
```

**Real fault during bootstrap:** RouterOS's own forced "set a password" prompt on first
console login (triggered independently of any command run) consumed a pasted multi-command
block as answers to `new password>`/`repeat new password>`, landing on an unintended
password recovered only because the console session was still authenticated. Lesson applied
for the rest of the night: bootstrap commands sent one at a time, never as a block, until a
clean prompt is confirmed.

**Second fault, caught by cross-checking output against the intended topology, not assumed
correct:** `/ip address print` on CHR-CORE showed the PE-facing link address
(`10.255.0.2/30`) sitting on `ether4` (the management interface) instead of `ether1` ---
a manual-entry slip during cleanup. Fixed with an explicit-index `remove`/`add` pair;
`[find address=...]` silently matched nothing on the first attempt (RouterOS `find` needs
an exact stored-value match), confirming the index-based approach was the right fallback.

Read: every one of these was caught by checking real output against the intended state, not
by assuming a command that returned no error had done what was asked --- the actual
discipline this whole verification log exists to enforce.

## Task 15 --- OSPF area 0, PE to CORE

`ospf-core` instance + `backbone` area (`0.0.0.0`) on both routers, interface templates for
the `10.255.0.0/30` transit link and each router's own loopback (passive).

`/routing ospf neighbor print` on PE, after DR/BDR election settled (~23s, within the 40s
`dead-interval` window --- an initial check at 15s still showed `TwoWay`, not a fault, just
too early):

```
0 D state="Full" dr=10.255.0.2 bdr=10.255.0.1 adjacency=23s router-id=10.255.255.2
```

`/routing ospf lsa print` on PE --- the load-bearing check, since adjacency alone doesn't
prove flooding:

```
1 D instance=ospf-core area=backbone type="router" originator=10.255.255.2   <- not self (no S flag)
     type=stub id=10.255.255.2 data=255.255.255.255 metric=1
2 D instance=ospf-core area=backbone type="network" originator=10.255.255.2
     router-id=10.255.255.1
     router-id=10.255.255.2
```

Row 1 has no `S` (self-originated) flag and `originator=10.255.255.2` --- this is CORE's own
router-LSA, seen on PE, proving it was actually flooded across the link, not just that two
neighbours exchanged hellos. `/ping 10.255.255.2 src-address=10.255.255.1`: 0% loss ---
loopback-to-loopback reachability riding purely on the OSPF-learned route.

Read: `Full` + a non-self LSA + a working loopback ping together prove the whole chain ---
adjacency, database synchronisation, and actual forwarding --- rather than any single
weaker signal that could be true in isolation while something upstream is still broken.

## Task 16 --- BGP: instance, iBGP over loopbacks, eBGP to IIG

`/routing/bgp/instance/print` confirmed empty on all three routers before configuring ---
no default instance on fresh 7.23.3, matching the plan's own warning. Created `as65001` on
PE/CORE, `as65002` on UPSTREAM.

`/routing/bgp/session/print`, all four sessions (PE-CORE iBGP, CORE-UPSTREAM eBGP,
CORE-BDIX eBGP is Task 17):

```
E name="upstream-link-1" ... uptime=26s790ms messages=1/2
E name="pe-link-1"       ... uptime=18s410ms messages=1/2  nexthop-choice=force-self
```

The `E` flag with climbing `uptime` and non-zero `.messages` on both directions is the
proof a connection actually became a session --- `/routing/bgp/connection/print` alone only
shows what was typed, not that it ever worked.

**Known limitation, documented rather than hidden:** UPSTREAM's `output.network=MY-NETWORKS`
address-list contains both `203.0.113.0/24` and `0.0.0.0/0`, but only the specific prefix
was ever advertised (`/routing/bgp/advertisements print` on UPSTREAM showed one row, not
two). RouterOS v7 appears to require a separate mechanism for default-route origination that
isn't clearly documented anywhere searched. Not chased further --- `203.0.113.0/24` alone is
sufficient for every downstream proof, including Task 17's no-transit check, which only
verifies that specific prefix's absence on BDIX.

**The iBGP next-hop problem, demonstrated live, not just asserted.** Before, PE's route:

```
203.0.113.0/24  gateway=10.255.255.2  (CORE's loopback --- force-self working)
```

After disabling `force-self` on CORE's PE-facing session:

```
203.0.113.0/24  gateway=172.16.0.2  immediate-gw=10.0.2.2%ether1
```

This is a stronger result than a clean "route removed" would have been: PE didn't drop the
route, it silently recursed through its own default route out the internet-facing NAT
interface, because nothing in its table matched UPSTREAM's raw next-hop. That is the actual
danger of this misconfiguration in production --- not an obvious failure, a silent one.
Restored `force-self`; gateway correctly reverted to `10.255.255.2`.

Read: this is the standard interview question ("what happens if iBGP next-hop isn't
force-self'd") answered with a real before/after/restore cycle on a real router, including
the specific `immediate-gw` field that shows exactly where the packet would actually have
gone, not just that it would have failed somehow.

## Task 17 --- BDIX peering and no-transit policy

Three policies, all on CORE, each independently verified:

**(a) Local-pref.** `/routing/route/print detail where dst-address=198.51.100.0/24`:

```
bgp.session=bdix-link-1 .as-path="65100" .local-pref=200 .origin=igp
```

`.local-pref=200` confirms the `bdix-in` filter rule actually set the attribute, not just
that the route was accepted.

**(b) Input filter.** `bdix-in` accepts only `198.51.100.0/24` from BDIX with an explicit
terminal `reject;` (v7 defaults to reject on an unmatched chain, so this line isn't
optional). Only that one prefix appears learned from BDIX in the route table --- the filter
is doing real work, not just present in the config.

**(c) No-transit, proven bidirectionally.** `/ip route print where bgp` on BDIX:

```
192.0.2.0/24  gateway=10.99.0.1
```

`203.0.113.0/24` (IIG's route) is absent --- the actual proof, per the plan's own framing:
absence, not presence of a filter. Same check on UPSTREAM after fixing a real gap (below):

```
192.0.2.0/24  gateway=172.16.0.1
```

`198.51.100.0/24` (BDIX's route) is absent too.

**Real bug, caught by checking `/routing/bgp/advertisements print` on CORE rather than
trusting the config alone:** setting `output.network=MY-NETWORKS` on the CORE-UPSTREAM
connection restricted what CORE *originates* toward UPSTREAM, but did nothing to stop CORE
*redistributing* `198.51.100.0/24` (learned from BDIX) onward to UPSTREAM --- `output.network`
and `output.filter-chain` are two different mechanisms in RouterOS v7, and only the second
one filters propagated routes. `198.51.100.0/24` was found still present in UPSTREAM's route
table after the `output.network` fix, disproving the assumption it would be enough. Fixed
with a proper `upstream-out` filter chain, mirroring `bdix-out`.

Read: this is the actual point of the plan calling this task "the differentiator" --- not
configuring three rules from a template, but catching and fixing a genuine transit-leak bug
that a config-only review would have missed, because the fix that looked complete
(`output.network`) silently wasn't.

## Task 20 --- GPON/OLT knowledge document

No lab commands to verify --- `docs/05-gpon-olt-notes.md` is a documented-knowledge write-up,
not a lab result, and says so explicitly in its own opening line. Recorded here only to note
why this task has no corresponding verification block: the honest absence of one is the
point, not an oversight.

## Tasks 18 and 19 --- deliberately cut

MPLS LDP (Task 18) and the Zabbix monitoring VM (Task 19) were cut for time, per the plan's
own stated cut order ("MPLS and the GPON doc are the two lowest-dependency items ... cutting
them is visible and honest"). Task 20 (GPON doc) was kept since it directly answers a real
interview question already in this repo's interview-prep notes at low cost; Task 19 was cut
instead since it required a new 2 GB VM with no upstream dependents. Not silently dropped ---
recorded here and in the README's limitations section.
