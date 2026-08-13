# GPON / OLT knowledge notes

**No OLT hardware was involved in building this repository, and nothing in this document is a
verified lab result.** Everything below is documented knowledge, written to answer the FTTx
interview question honestly rather than to claim hands-on experience this repo cannot back. Where
BD vendors are named, it is because they were encountered in job postings and market research, not
because any of their equipment was operated.

---

## 1. PON topology and split ratio

GPON (Gigabit Passive Optical Network) is a point-to-multipoint architecture: one fibre from the
OLT (Optical Line Terminal, at the ISP's central office or a local POP) feeds a passive optical
splitter, which fans out to many ONUs/ONTs (Optical Network Unit/Terminal, at the customer
premises) over individual fibre drops. "Passive" is the key word -- the splitter has no power, no
electronics, nothing to fail in the way an active Ethernet switch can.

- **Split ratios:** commonly 1:32 or 1:64 per PON port, sometimes 1:128 with cascaded splitters.
  Higher splits mean more subscribers per OLT port but a tighter optical power budget per ONU.
- **Downstream:** OLT broadcasts to every ONU on the PON at 2.488 Gbps (GPON); each ONU only
  decrypts the traffic addressed to it (GPON encryption, AES-128, protects subscriber isolation
  since every ONU physically receives every other subscriber's downstream frames).
- **Upstream:** 1.244 Gbps, shared, using TDMA -- the OLT assigns each ONU a transmission timeslot
  (DBA, Dynamic Bandwidth Allocation) so upstream transmissions from different ONUs never collide
  on the shared fibre.
- **Reach:** typically up to 20 km from OLT to ONU, though the practical distance in a BD FTTx
  deployment is usually much shorter, governed by the power budget (see Section 3), not the
  standard's theoretical maximum.

## 2. ONU registration states

When an ONU is connected to a live PON port, it goes through a defined sequence before it can pass
traffic. Each state has a specific meaning for troubleshooting:

| State | Meaning | What a stuck state at this stage implies |
|---|---|---|
| **O1 -- Initial** | ONU powered off / not yet ranging | No fibre continuity, or ONU has no power |
| **O2 -- Standby** | ONU is listening for a matching OLT | OLT not transmitting on this PON port, or ONU firmware/PON standard mismatch |
| **O3 -- Serial number** | OLT sees the ONU's serial number, ranging in progress | Distance-ranging in progress -- normal transient state |
| **O4 -- Ranging** | OLT is measuring round-trip delay to assign the ONU's TDMA timeslot | Prolonged O4 usually means marginal optical power, not a logic fault |
| **O5 -- Operation** | ONU is fully registered, DBA active, ready to pass traffic | This is the target steady state |
| **O6/O7 -- Intermittent LOS / emergency stop** | ONU was in O5 but lost sync | Points to a physical-layer problem, not config -- see Section 4 |

A registration process that repeatedly cycles O3 -> O4 -> O1 (never reaching O5) is the classic
symptom of an optical power problem: the OLT can briefly see the ONU during ranging but the link
margin is too thin to hold a stable connection. This is functionally the RF equivalent of a WiFi
client that can associate but can't stay connected -- the physical layer is marginal, not broken.

## 3. Optical power budget

Every PON link has to fit a real power budget: OLT transmit power, minus splitter loss, minus
fibre attenuation and connector losses, must land inside the ONU's receiver sensitivity window.

- **Typical GPON OLT Tx power:** +1.5 to +5 dBm (Class B+) or up to +7 dBm (Class C+, for longer
  reach / higher splits).
- **Typical splitter loss:** roughly 17 dB for a 1:32 split, roughly 20-21 dB for a 1:64 split
  (splitting power in half costs ~3 dB, so each doubling of the split ratio costs another ~3 dB).
- **Fibre + connector loss:** roughly 0.35 dB/km for the fibre itself, plus ~0.5 dB per connector
  pair and ~0.1-0.5 dB per fusion splice -- usually small relative to splitter loss over FTTx
  distances, but every dirty or poorly-terminated connector adds up.
- **Normal ONU receive power range:** roughly -8 dBm to -27 dBm is the usual GPON Class B+
  receiver sensitivity window; many vendors flag anything below about -25 dBm as "optical power
  low" even though the ONU may still technically link up, because there is almost no margin left
  for further degradation (a bent fibre, a dirtier connector, a hot day) before the link drops
  entirely.
- **Rule of thumb for troubleshooting:** a received power reading near the edge of spec (e.g.
  -26 to -28 dBm) that still shows O5/operational is not "fine" -- it is a link that will be the
  first to fail on the next minor degradation, and is worth proactively re-terminating or
  re-splicing before it becomes a customer complaint.

## 4. LOS and dying-gasp alarms

- **LOS (Loss of Signal):** the OLT (or ONU) is receiving no optical signal at all on the PON
  wavelength it expects. Causes range from a fully cut fibre, a disconnected/dirty connector, a
  powered-off ONU, to a bend radius violation sharp enough to attenuate the signal below detection.
  LOS is a hard physical-layer fault -- there is no software fix, only a physical one.
- **Dying gasp:** a GPON-specific alarm the ONU sends the instant it loses AC/DC power, using the
  brief energy stored in its power-supply capacitors to transmit one last OMCI message before it
  goes dark. This is what lets an OLT (and, upstream of that, an NMS/monitoring system) distinguish
  "customer's ONU lost power" (dying gasp received, then LOS) from "fibre was cut" (LOS with no
  dying gasp) -- a real diagnostic signal, not just a generic disconnect.

## 5. Troubleshooting decision tree: "customer reports no internet"

```
Customer reports no internet
|
+-- Check ONU registration state on the OLT (O1-O7)
|   |
|   +-- O5 (Operational)? -> physical layer is fine, problem is likely
|   |                        upstream (PPPoE/DHCP auth, ISP-side config,
|   |                        or the customer's own router/LAN) -- treat
|   |                        as a Layer 3+ problem, not an optical one
|   |
|   +-- Stuck at O1 (Initial)? -> check for dying-gasp alarm
|   |   |
|   |   +-- Dying gasp received -> ONU lost power (outage, unplugged
|   |   |                          adapter, tripped breaker at premises)
|   |   |
|   |   +-- No dying gasp, straight to LOS -> suspect a physical cut or
|   |                                        disconnection somewhere
|   |                                        between OLT and ONU
|   |
|   +-- Cycling O3 -> O4 -> O1 repeatedly, never reaching O5?
|   |   -> optical power marginal -- check received power reading
|   |      against the -8 to -27 dBm window; if near the low end,
|   |      suspect a dirty/bad connector, excessive splice loss, or
|   |      a fibre bend violation
|   |
|   +-- O2 (Standby) indefinitely? -> ONU can't see a matching OLT
|       signal -- check the OLT PON port is actually transmitting,
|       and that ONU firmware/PON generation matches the OLT
|
+-- If registration looks healthy but no optical power reading is
    available at all -> escalate to a physical fibre inspection
    (a technician with an optical power meter and, if needed, an OTDR
    to find the exact break/degradation point along the fibre run)
```

The general principle: **ONU registration state plus the dying-gasp/LOS distinction narrows the
problem to "physical layer" vs "everything above it" almost immediately**, before any truck roll.
That triage step is most of what a NOC/L1 role is actually doing on a GPON fault -- not fixing the
fibre themselves, but correctly routing the ticket to a field technician with the right diagnosis
already attached, or correctly keeping it in-house as a Layer 3 problem.

## 6. Vendors encountered in BD job postings

Named here because they appeared in market research on BD ISP/FTTx job postings, not because any
were operated: **Huawei** (widely deployed OLT/ONU hardware across BD ISPs), **VSOL**, **CDATA**
(both common lower-cost GPON vendors seen in smaller BD ISP deployments). No claim of familiarity
with any specific vendor's management interface beyond what is documented here.
