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
