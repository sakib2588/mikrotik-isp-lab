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
