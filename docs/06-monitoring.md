# SNMP-based network monitoring --- Zabbix

## Why and which tool

Named in 6 of 14 postings, and directly by NGO ONLINE BD (The Dude, LibreNMS, MRTG). Zabbix
was chosen over LibreNMS and The Dude: Zabbix and LibreNMS are both named by more postings than
The Dude, and Zabbix runs cleanly in Docker with no Wine dependency, unlike The Dude's
Windows-only client. **Only Zabbix is claimed on the CV** --- LibreNMS was not installed.

## What SNMP already existed vs. what this task added

CHR-PE already had `/snmp community` configured (community `lab-ro`, restricted to
`192.168.56.0/24`) from earlier lab work. CHR-CORE, CHR-UPSTREAM and CHR-BDIX did **not** ---
they were added later as Task 10's stretch routers and never got SNMP. Verified live before
assuming otherwise:

```
$ snmpwalk -v2c -c lab-ro -t2 192.168.56.10 1.3.6.1.2.1.1.5   # CHR-PE: answers
$ snmpwalk -v2c -c lab-ro -t2 192.168.56.12 1.3.6.1.2.1.1.5   # CHR-CORE: timeout
```

Fixed by applying the identical `/snmp community` and `/snmp` config CHR-PE already carried to
all three, over SSH. All four routers answer SNMP on `lab-ro` now:

```
192.168.56.10 -> CHR-PE
192.168.56.12 -> CHR-CORE
192.168.56.13 -> CHR-UPSTREAM
192.168.56.14 -> CHR-BDIX
```

CHR-CPE is deliberately not in the NMS. It has no host-reachable management interface by
design (see `docs/02-build-notes.md`) --- the same reason it isn't SSH-reachable day to day.
A real ISP does not typically poll customer CPEs directly from the core NMS either.

## Build

Before `docker compose up`, create `nms-setup/.env` (gitignored, never committed) with:

```
ZBX_DB_PASSWORD=<pick a password>
ZBX_DB_ROOT_PASSWORD=<pick a different password>
```

`nms-setup/docker-compose.yml` --- a minimal three-container Zabbix 7.0 stack (MySQL 8,
`zabbix-server-mysql`, `zabbix-web-nginx-mysql`), web UI on `localhost:8081`. Brought up with
`docker compose up -d`; schema and server startup confirmed complete from the server log rather
than assumed from container status.

Hosts were added through the Zabbix JSON-RPC API rather than the web UI --- scriptable,
reviewable, and avoids hand-clicking four near-identical host forms:

```bash
curl -s http://localhost:8081/api_jsonrpc.php -d '{
  "jsonrpc":"2.0","method":"host.create",
  "params":{
    "host":"CHR-PE",
    "interfaces":[{"type":2,"main":1,"useip":1,"ip":"192.168.56.10","port":"161",
                   "details":{"version":2,"bulk":1,"community":"lab-ro"}}],
    "groups":[{"groupid":"22"}],
    "templates":[{"templateid":"10233"}]
  },"auth":"...","id":1}'
```

All four hosts use the built-in **"Mikrotik by SNMP"** template (Zabbix templateid 10233),
group `MikroTik ISP Lab`.

## What is polled

Interface counters, uptime, CPU/memory (where the RouterOS SNMP MIB exposes it), and the
built-in availability check --- Zabbix marks a host unavailable when SNMP polling fails, which
is the mechanism the outage test below relies on.

## Verification: all four routers green

```json
{"host":"CHR-PE","interfaces":[{"ip":"192.168.56.10","available":"1","error":""}]}
{"host":"CHR-UPSTREAM","interfaces":[{"ip":"192.168.56.13","available":"1","error":""}]}
{"host":"CHR-BDIX","interfaces":[{"ip":"192.168.56.14","available":"1","error":""}]}
{"host":"CHR-CORE","interfaces":[{"ip":"192.168.56.12","available":"1","error":""}]}
```

`available: "1"` is Zabbix's "available" state.

## Verification: outage detection, not just installation

A green dashboard proves installation. It does not prove monitoring. `VBoxManage controlvm
CHR-BDIX poweroff` was run while polling the API every 10 seconds:

```
check 0-8 (0-80s): available=1
check 9 (90s):     available=2
                    error: "cannot retrieve OID: '.1.3.6.1.2.1.1.3.0' from
                            [[192.168.56.14]:161]: timed out"
```

Zabbix flagged the outage within one polling cycle (SNMP checks default to ~60-90s intervals
in this build) and recorded the specific failure --- an SNMP timeout on the sysUpTime OID, not
a generic "down". The router was then powered back on and confirmed reachable again at the
network layer (`ping`, `snmpwalk`) before moving on.

## Honest limitation --- screenshots not yet captured

The two screenshots this task originally called for (all-green device list; the outage caught
live in the web UI) were **not captured**, because this session ran the whole task
non-interactively over SSH and the Zabbix API, with no browser driving the GUI. The evidence
above is the CLI/API-equivalent of both: the `host.get` output for the all-green state, and the
`available` flip plus SNMP timeout error for the outage state. **Still open:** log into
`http://localhost:8081` (Admin/zabbix), open Monitoring > Hosts, and capture the two screenshots
for the portfolio. Reproducing the outage for the second screenshot only needs
`VBoxManage controlvm CHR-BDIX poweroff` again.
