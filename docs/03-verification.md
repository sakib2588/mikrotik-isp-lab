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
either side's output alone. Screenshot: `screenshots/task07-04-ppp-active-print-pe.png`
(pending).

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
