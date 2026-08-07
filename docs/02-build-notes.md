# Build notes --- RouterOS CHR 7.23.3

-rw-r--r-- 1 filwel filwel 51M Jul 30 17:47 /home/filwel/Downloads/chr-7.23.3.vdi

## Incident: CHR-CPE lost credentials, rebuilt from scratch

During Task 7 Step 2/3, the admin password set on the first CHR-CPE console login was
forgotten before any config was exported or verified. RouterOS has no console-based
password-recovery mode --- unlike Cisco IOS there is no ROMMON-style reset. Since nothing
from CHR-CPE had been committed to this repo yet, the fix was to wipe the VM and rebuild
clean rather than attempt any recovery:

```bash
VBoxManage controlvm CHR-CPE poweroff
VBoxManage unregistervm CHR-CPE --delete
```

then recreated identically from the untouched image at `~/Downloads/chr-7.23.3.vdi` (the
pristine download is never modified in place --- every VM gets its own copy, which is
exactly what made this rebuild trivial). CHR-PE was unaffected throughout.

Lesson: for a lab VM with no committed state yet, rebuild beats recovery. Write down every
console password the moment it's set, before running the next command --- not after.

## Note: CHR-CPE ether3 was a temporary management path, not part of the design

CHR-CPE has no host-reachable interface by design --- only `lab-access` (facing CHR-PE)
and `cust-lan` (facing the customer side), no NAT adapter. That's deliberate: any traffic
it sends to the internet has to go through the PPPoE tunnel to prove the topology is real
(see docs/03-verification.md, Task 7 Step 5 traceroute).

To pull `/export hide-sensitive` from CHR-CPE onto the host, a third adapter was added
temporarily --- hostonly `vboxnet0`, address 192.168.56.11/24 on ether3 --- then removed
again immediately after the export. `configs/chr-cpe.rsc` still shows that address because
it reflects the config at the moment of export; the adapter itself is gone from the running
VM (`nic3=none`). If SSH access to CHR-CPE is needed again later, repeat the same
add-adapter / pull-file / remove-adapter sequence rather than leaving it attached
permanently.

## Deferred: Task 9 Steps 8-9, remote syslog to Wazuh manager

Manager address on file: `192.168.1.50` (static, always-on Arch laptop, confirmed against
the SOC lab repo's own `docs/Agent_Enrollment_Handover.md` --- ports 1514/1515). At the time
this lab reached Task 9, the manager did not answer ping from this host (192.168.1.106,
enp6s0): "Destination Host Unreachable". Likely the laptop was asleep or off in another
room, not a config problem on either side.

Deliberately did not add a bridged adapter to CHR-PE or point `/system logging` at a real
target while the manager's reachability couldn't be confirmed and the session was ending
for the night --- an unverified network-exposure change with nobody around to check it is
the wrong tradeoff. Skipped per the plan's own stated option ("skip this step and write in
the build notes why it was skipped"), not silently dropped.

**To finish later:**
1. Confirm the Arch laptop is up: `ping 192.168.1.50` from popos-mainpc.
2. `VBoxManage controlvm CHR-PE poweroff && VBoxManage modifyvm CHR-PE --nic4 bridged --bridgeadapter4 enp6s0 --nictype4 virtio && VBoxManage startvm CHR-PE --type gui`
3. On CHR-PE: `/ip dhcp-client add interface=ether4 disabled=no` (or a static address on
   the 192.168.1.0/24 segment, matching how DC-1 is set up).
4. `/system logging action add name=remote-syslog target=remote remote=192.168.1.50 remote-port=514`
   then `/system logging add topics=info action=remote-syslog` and the same for `topics=error`.
5. Trigger an event (toggle the WAN link as in Task 9 Step 7) and confirm on the manager:
   `sudo tail -f /var/ossec/logs/archives/archives.log | grep -i mikrotik`
