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
