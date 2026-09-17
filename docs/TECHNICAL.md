# Technical flow

## Proven MT6833 sequence

The verified path is:

1. Windows sees normal Android (`18D1:4EE7`) or no phone.
2. The phone is power-cycled into MediaTek BROM.
3. mtkclient identifies `MT6833 (Dimensity 700 5G k6833)`.
4. Security is bypassed with the MT6833 Kamakiri payload.
5. XFlash DA stage 1 is patched and uploaded.
6. EMI/DRAM setup completes.
7. XFlash DA stage 2 is uploaded.
8. UFS is enumerated.
9. DA extensions are loaded.
10. `seccfg` is parsed and the requested lock state is handled.

The read-only `preflight.ps1` stops at GPT enumeration. It does not write `seccfg`.

## State handling

mtkclient writes `.state` after a successful DA upload. That state is useful only while a compatible DA session is actually alive. Reusing it after a phone reset caused a false reinitialization path and the exact `GET_RAM_INFO`/12-byte-header exception documented in troubleshooting.

Before every hardware process, this toolkit moves `.state` to `.state.stale-<timestamp>`. It does not silently delete the evidence.
## Success evidence

A wrapper-generated sentence is not proof. The accepted conditions are:

- process exit code `0`; and
- MT6833 evidence in the same run; and
- either upstream `Device is already unlocked` or `Successfully wrote seccfg.`

For the read-only gate, all of these must appear:

- `BROM mode detected.`
- `DRAM setup passed.`
- `Successfully uploaded stage 2`
- `GPT Table:`

## Upstream pin

The toolkit pins `bkerler/mtkclient` commit:

`cd25cf9c1ff6d36e82697ac2c798e69e9cfb78c3`

This was both the hardware-verified revision and upstream HEAD when this repository was created on 2026-09-17. Pinning makes the workflow reproducible; maintainers should re-test hardware before changing it.

## Post-unlock workflow architecture

`src/Workflow.psm1` adds the shared invariants used by the ROM/root stages: A/B slot normalization, artifact SHA-256 gates, verified device-profile matching, ADB/Fastboot state polling, stable Magisk release metadata parsing, Android boot-image validation, sideload evidence parsing, and atomic resume-state handling.

`config/verified-camellia.json` is the hardware-tested artifact contract. A command is not allowed to write a boot partition or sideload an image merely because a filename looks plausible; the local bytes must match the manifest hash first.

The Lineage target has no `init_boot` or separate `recovery` partition. Its recovery-bearing source `boot.img` is Android boot header v2 with a real ramdisk. Consequently the verified Magisk flow patches that exact boot image and selects `boot_a` or `boot_b` only from the live active-slot evidence.

`install-all.ps1` is an orchestrator rather than a bypass layer. Every stage retains its own gates. `-WhatIf` is hardware-free and writes no resume state. Physical BROM/recovery/PIN actions remain explicit human boundaries.