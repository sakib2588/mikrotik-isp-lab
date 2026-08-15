# RPKI route origin validation --- CHR-CORE

## Why

Driven by **ZHB Solutions** (Nikunja, deadline 09 Sep), whose second responsibility is
verbatim: *"Set up and maintain IRR route objects and RPKI ROAs for our IP space."* Their first
and third responsibilities --- BGP with multiple upstream transit providers, multihomed
failover validation --- are already evidenced by this lab's existing BGP build. RPKI closes the
remaining gap on the closest skills match seen among any target posting so far.

**Why this is the highest-differentiation item in the plan:** BGP alone is already rare for a
Bangladeshi fresher. BGP *with origin validation configured and demonstrably rejecting a bad
route* is something most working network engineers in Dhaka have not built.

## What a ROA actually proves

A ROA (Route Origin Authorization) is a signed statement that a given AS is authorised to
originate a given prefix. RPKI lets a router check a received BGP route against those
statements and label it `valid`, `invalid`, or `not-found` (no ROA covers it at all). It is the
defence against route hijacking --- the same class of failure as the transit leak already
documented in `docs/04-troubleshooting-log.md`, just caught by cryptographic policy instead of
by noticing traffic in the wrong place after the fact.

## Design decision: a local ROA set, not the real global RPKI table

The first attempt pointed CHR-CORE at a full internet-facing validator (Routinator with the
bundled RIR TALs) and hit two real problems in sequence:

1. **CHR-CORE ran out of memory.** The default CHR allocation in this lab was 256 MB. The full
   global VRP set is roughly 990,000 entries across the five RIRs. `/system resource print`
   showed 11.7 MiB free with the RTR session stuck mid-sync. Fixed by powering the VM off,
   raising its allocation to 768 MB (`VBoxManage modifyvm CHR-CORE --memory 768`), and powering
   back on --- comfortably enough headroom, confirmed by `free-memory: 543.2MiB` at boot.
2. **The full table still wasn't the right tool for this demonstration even once it fit.** None
   of this lab's own address space (`192.0.2.0/24`, `203.0.113.0/24`, `198.51.100.0/24` --- all
   RFC5737/RFC5389 documentation ranges) has a real-world ROA, so the global dataset would never
   actually exercise the one route this lab controls end to end.

The fix for both: Routinator's `--no-rir-tals` flag drops the bundled RIR trust anchors
entirely, and `-x rpki-setup/slurm-exceptions.json` (RFC 8416 SLURM format) adds exactly one
locally-asserted ROA covering the one prefix CHR-CORE actually receives inbound from
CHR-UPSTREAM's eBGP session (`203.0.113.0/24`, origin AS65002). Sync time dropped from "still
not finished after 96+ seconds and climbing" to instantaneous (`last-update-duration:
PT0.000231687S`, `final-vrps: 1`).

This is a deliberately narrow, controlled dataset built to test one specific route --- the same
philosophy as the CGNAT and BGP transit-leak faults already documented elsewhere in this repo:
a fault caused on purpose, with a known-correct expected outcome, beats depending on
uncontrolled real-world data for a lab demonstration.

## Validator

`nlnetlabs/routinator`, Docker, RTR on port 3323, HTTP status API on 9556:

```bash
docker run -d --name rpki-validator -p 3323:3323 -p 9556:9556 \
  -v "$(pwd)/rpki-setup:/exceptions:ro" \
  nlnetlabs/routinator --no-rir-tals -x /exceptions/slurm-exceptions.json \
  server --rtr 0.0.0.0:3323 --http 0.0.0.0:9556
```

`rpki-setup/slurm-exceptions.json` is the single source of truth for what CHR-CORE will
validate as `valid` --- see the file for the one asserted ROA and the comment explaining it.

## Router configuration

```
/routing rpki add group=rpki-main address=192.168.56.1 port=3323 disabled=no

/routing filter rule add chain=upstream-in \
    rule="rpki-verify rpki-main; if (rpki invalid) { reject } else { accept }"
/routing bgp connection set [find name=upstream-link] input.filter=upstream-in
```

**Finding the correct filter syntax took three wrong guesses.** `rpki-verdict=invalid` (the form
half-remembered from general RPKI reading) is not a recognised matcher on RouterOS 7.23 ---
every variant of it returned `unknown matcher`. The actual RouterOS syntax calls `rpki-verify
<group-name>` as a statement first, which populates a `rpki` variable for that rule, then tests
it with the bare identifier: `if (rpki invalid) { ... }` / `if (rpki valid) { ... }`. Confirmed
against MikroTik's own RPKI documentation before touching the router again, rather than guessing
a fourth time.

**`/routing rpki session print` reports `state=sync` even once fully loaded and current.** That
reads like a stuck transient state (and was treated as one for a few minutes of debugging), but
it is RouterOS's steady-state label for an established RTR session, not a symptom of anything
wrong --- confirmed once the *filter* result changed correctly on demand despite the session
never showing a state called `established`. The router log's `Group rpki-main cache merge` line
is the more reliable signal that a refresh actually completed.

## Verification: both directions, before and after

**Valid --- route accepted**, using the correct ROA (`asn=65002` for `203.0.113.0/24`):

```
[admin@CHR-CORE] > /routing route print detail where dst-address=203.0.113.0/24
 Ab   dst-address=203.0.113.0/24 gateway=172.16.0.2
      rpki=valid
      bgp.session=upstream-link-1 .as-path="65002" .origin=igp
```

`A` flag --- active, in the routing table, usable.

**Invalid --- route rejected**, after editing the SLURM file's `asn` to `65999` (a deliberately
wrong origin for the same real-world advertisement, which still arrives with `as-path="65002"`)
and restarting the validator so it re-synced:

```
[admin@CHR-CORE] > /routing route print detail where dst-address=203.0.113.0/24
 Fb   dst-address=203.0.113.0/24 gateway=172.16.0.2
      rpki=invalid
      bgp.session=upstream-link-1 .as-path="65002" .origin=igp
```

`F` flag --- filtered, present in BGP's input but rejected by the routing filter, not usable.
**No BGP session reset or manual filter refresh was needed** --- CHR-CORE re-evaluated the
existing route against the updated RPKI data automatically as soon as the RTR session
resynchronised. The ROA was then restored to the correct `asn=65002` value and the route
returned to `valid`/active --- the lab's resting state is healthy, this was a deliberate,
reversed excursion, the same pattern as every other caused-and-fixed fault in this repo.

## `unknown` verdict --- the correct real-world default

Not tested directly in this lab (there is no second prefix to demonstrate it against), but
worth stating for the record because it is the answer that separates someone who has read about
RPKI from someone who has operated it: routes with **no covering ROA at all** get verdict
`not-found`/`unknown`, and the filter above --- `if (rpki invalid) { reject } else { accept }`
--- explicitly **accepts** unknown routes rather than rejecting them. A large share of global
routing is still unsigned; treating "unknown" the same as "invalid" would black-hole most of the
internet. Only a confirmed mismatch between an announced route and an existing ROA gets
rejected.

## IRR route objects --- deliberately not built, and why

IRR (Internet Routing Registry) route objects are a related but separate mechanism from RPKI
ROAs: an IRR object is an unsigned database record (in RADB, ARIN, APNIC, etc.) saying "this AS
originates this prefix," historically used to auto-generate router filters; a ROA is a
cryptographically signed RPKI object saying the same thing, verifiable without trusting the
registry operator. ZHB's posting names both.

**IRR objects cannot be labbed honestly.** They require a real, registered ASN and a registry
account --- there is nothing to fake that would be worth having. Consistent with how this repo
already handled the GPON/OLT gap (`docs/05-gpon-olt-notes.md`): state plainly that it was not
built, and that the reason is a real-world prerequisite (a registered ASN) that a home lab
cannot fabricate, rather than improvising a hollow substitute. Knowing the distinction between
an IRR object and a ROA, and being honest about which one is actually demonstrated here, is
itself the stronger interview answer.
