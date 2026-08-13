# Troubleshooting log --- Phase 2

One entry per real fault hit while building Tasks 11-17 and 20. A lab with no recorded faults
reads as fabricated; this is the honest record of what actually broke and how it got fixed.
Ordered by when each was hit, not by severity.

## 1. RADIUS shared-secret confusion (Task 11)

First `radtest` attempt used the wrong trailing secret --- the last argument to `radtest` is
the shared secret for the `localhost` client entry in `clients.conf`, not related to the
test account's own password. Typed a guessed value instead of checking the file first.
FreeRADIUS's debug output (`freeradius -X`) named the exact cause:
`Shared secret is incorrect`. Fixed by grepping `clients.conf` directly
(`grep -nE "^\s*secret\s*=" clients.conf`) instead of guessing. Lesson: when an auth failure
gives a specific reason, read it before retrying with a different guess.

## 2. Multi-line command paste mangling (recurring, Tasks 11-17)

RouterOS's `\` line-continuation syntax and bracketed `[find ...]` filters both broke
repeatedly when pasted as part of a larger block into an SSH terminal --- sometimes silently
concatenating lines into one malformed command, sometimes leaving the console stuck in an
interactive sub-prompt (`numbers:`) that then consumed subsequent pasted lines as answers
rather than commands. Worst instance: a forced RouterOS password-change prompt on a fresh
CHR-CORE console ate several lines of an intended `/system identity`/`/ip address` block as
password-change answers, landing on an unintended password. Recovered because the console
session was still authenticated. Fixed going forward by sending commands one at a time and
confirming a clean prompt before sending the next, and by using explicit `numbers=` instead
of `[find ...]` wherever possible. This is the single most repeated fault of the night.

## 3. Forgotten CHR-PE / CHR-CPE admin passwords (mid-session)

Both routers' admin passwords were forgotten mid-session. RouterOS has no console-based
password recovery (confirmed against this repo's own earlier incident with CHR-CPE in
`02-build-notes.md`, where the fix at the time was a full VM rebuild). This time, recovery
was possible without rebuilding: a short list of likely passwords (patterns reused elsewhere
in this session) tried via `sshpass` against SSH, since RouterOS doesn't lock out failed
attempts. Cracked in 2 attempts (`sakib`) on both routers. Real finding: this password
doubled as the RADIUS shared secret for `chr-pe`'s client entry too --- one weak, reused
credential compromising both the management plane and a trust relationship simultaneously.
Flagged to the operator; accepted as-is for a home lab, documented here rather than silently
left unmentioned.

## 4. CGNAT generator script property name (Task 12)

MikroTik's own published CGNAT script (fetched from `help.mikrotik.com`) used `to-address=`
in the version retrieved; RouterOS's actual NAT property is `to-addresses` (plural, confirmed
via a second, independent search). Using the wrong property name would have silently created
a broken rule. Caught before deployment by cross-checking against a second source rather than
trusting a single doc fetch --- the fetched page's own AI-summarised text is not guaranteed
byte-accurate to the source.

## 5. NAT rule-order shadow bug (Task 12)

The pre-existing Phase 1 masquerade rule (unconditional, no `src-address` filter) sat above
the new CGNAT jump rule in the `srcnat` chain. RouterOS evaluates NAT rules top-to-bottom and
masquerade is a terminal action, so every packet --- including subscriber traffic meant for
the deterministic CGNAT chain --- was masqueraded before the CGNAT rules were ever reached.
`/ip firewall nat print stats` showed the masquerade rule's packet counter climbing while
every CGNAT rule stayed at zero, confirming the diagnosis before attempting a fix. Fixed with
`/ip firewall nat move numbers=1 destination=0`, placing the CGNAT jump rule (scoped only to
the subscriber pool) above the unconditional masquerade rule.

## 6. Firewall filter self-block (Task 12)

MikroTik's own documented RFC 6598 ingress-filter rule
(`chain=forward src-address=100.64.0.0/10 action=drop out-interface=ether1`) is written for a
boundary/peering router separate from the node performing CGNAT. In this lab, CHR-PE does
both jobs on the same interface, so the rule matched every subscriber's own outbound packet
--- source is still in the CGN range at the `forward` filter stage, since NAT translation
happens later in `postrouting` --- and silently dropped it before NAT ever ran. Diagnosed by
checking CHR-PE's own WAN reachability (fine) against a completely empty connection-tracking
table for subscriber traffic (should not have been empty), then confirmed via
`/ip firewall filter print stats` showing nonzero packets on that specific rule. Removed;
the other 4 anti-spoof rules (which don't touch subscriber-sourced traffic) were kept.

## 7. Field name drift: `reply-src-port` vs `reply-dst-port` (Task 12)

The build plan's proof commands reference `reply-src-port` as the field holding the
CGNAT-allocated public port. On RouterOS 7.23.3, that field is actually `reply-dst-port`
(`reply-src-port` holds the remote server's own port, unchanged by translation). Documented
in `03-verification.md` rather than silently using the wrong field name in the write-up.

## 8. Git commits never actually landed (discovered before Task 14)

Tasks 11 and 12 were each given a `git commit` command to run at the end of their proof
cycle, but the session moved straight into debugging the next task without circling back to
actually execute them. Discovered only when checking `git log` before starting Task 14 and
finding neither commit present, plus `configs/cgnat-generator.rsc` still untracked. Fixed by
pulling a fresh `/export hide-sensitive` from the live router (capturing the true current
state) and committing it as one consolidated commit covering all three tasks, with the gap
explained in the commit message rather than pretending it was three atomic commits.

## 9. VirtualBox `createvm` ostype string (Task 14)

`VBoxManage createvm --ostype "Other Linux (64-bit)"` failed with
`Unknown or invalid guest OS type given` --- that string is the *display name* shown by
`showvminfo`, not the machine-readable ID `createvm` expects. Found the correct ID
(`Linux_64`) via `VBoxManage list ostypes`.

## 10. CHR-CORE address misassignment (Task 14)

During bootstrap cleanup on CHR-CORE, the PE-facing link address (`10.255.0.2/30`) ended up
assigned to `ether4` (the management interface) instead of `ether1`, leaving `ether1`
unaddressed and `ether4` carrying two addresses. Not caught by RouterOS (no error, the
command succeeded) --- caught by reading `/ip address print` output against the intended
topology rather than assuming success from a lack of error. First removal attempt used
`[find address=10.255.0.2/30]`, which matched nothing (silent no-op, no error) --- switched
to removing by explicit numeric index instead, which worked.

## 11. `type=blackhole` is not valid RouterOS v7 syntax (Task 16)

`/ip route add dst-address=X type=blackhole` failed with `bad parameter type`. RouterOS v7
uses a bare `blackhole` keyword as a standalone parameter, not a `type=` property (same
pattern as `passive` on OSPF interface-templates). Correct form:
`/ip route add dst-address=X blackhole`.

## 12. Default route origination via `output.network` doesn't work (Task 16, unresolved)

`0.0.0.0/0` was added to the same firewall address-list as `203.0.113.0/24` and given a
matching blackhole route, exactly as done for the specific prefix --- but
`/routing/bgp/advertisements print` showed only the specific prefix ever actually
advertised. Search results suggest RouterOS v7 requires a separate, undocumented mechanism
for default-route origination distinct from `output.network`/address-list matching. Not
resolved --- `203.0.113.0/24` alone was sufficient for every downstream proof this lab
needed, so this was logged as a known limitation rather than chased further under time
pressure. Worth revisiting if a future task specifically needs a working default route.

## 13. `output.network` does not filter propagated (non-self-originated) routes (Task 17)

Restricting CORE's `output.network` to `192.0.2.0/24` on its UPSTREAM-facing connection was
assumed to fully control what CORE sends toward UPSTREAM. It didn't: `198.51.100.0/24`
(learned from BDIX) kept being advertised to UPSTREAM regardless, because `output.network`
only gates which of a router's *own originated* prefixes get sent --- it has no effect on
routes learned from one peer and redistributed to another. Caught by checking
`/routing/bgp/advertisements print` on CORE directly rather than trusting the config change
was sufficient, then confirmed by checking UPSTREAM's actual route table after the change and
finding the leak still present. Fixed with a proper `output.filter-chain` (mirroring the
existing `bdix-out` chain), which does filter propagated routes. This is the actual
distinction RouterOS draws between the two mechanisms, and the bug that made Task 17's
"no-transit" claim briefly false in one direction while looking correct in the other.

## 14. RouterOS VM clock drift (noticed during Task 11 log review)

Log timestamps on CHR-PE showed dates roughly six days behind the host's real date (no NTP
client configured on a fresh CHR boot, no persistent RTC across VM snapshot/restore cycles).
Not a functional problem for anything in this lab --- BGP/OSPF timers and session states are
all relative, not wall-clock-dependent --- but worth noting so a future reader isn't confused
by out-of-order-looking timestamps in exported logs. FreeRADIUS's own accounting timestamps
(from the host, which has a correct clock) were used as the reliable reference where dates
mattered.
