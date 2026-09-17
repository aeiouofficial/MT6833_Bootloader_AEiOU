# MT6833 Bootloader AEiOU

A Windows-first, reproducible bootloader-unlock workflow for MediaTek MT6833 / Dimensity 700 devices using the actively maintained upstream [bkerler/mtkclient](https://github.com/bkerler/mtkclient).

This repository contains **the exact mtkclient source snapshot used for the verified unlock, AEiOU hardening, wrapper scripts, safety checks, tests, and documentation**.

## Verified hardware

Hardware-tested on 2026-09-17:

- Xiaomi Redmi Note 10 5G (`M2103K19G`)
- Device codename: `camellian`
- EEA product: `camellian_eea`
- SoC: MediaTek MT6833 / Dimensity 700 5G
- UFS model: `MT128GASAO4U21`
- Tested firmware: MIUI `V14.0.4.0.TKSEUXM`
- mtkclient: `2.1.4`, commit `cd25cf9c1ff6d36e82697ac2c798e69e9cfb78c3`

Other MT6833 devices may behave differently. Do not assume compatibility solely from the chipset name.

## Bundled AEiOU mtkclient fork

`vendor/mtkclient` is the complete source/loader snapshot used by this project, based on upstream `bkerler/mtkclient` commit `cd25cf9c1ff6d36e82697ac2c798e69e9cfb78c3` (2.1.4). It is bundled so users run the same code path that was verified on hardware rather than an arbitrary future checkout.

AEiOU hardening is documented in `vendor/mtkclient/AEIOU_FORK.md`. The key source change is in `mtkclient/Library/DA/mtk_da_handler.py`: persisted `.state` is **not automatically re-used** unless `MTKCLIENT_ALLOW_STATE_REINIT=1` is explicitly set. This prevents the stale-DA `GET_RAM_INFO` failure reproduced during MT6833 debugging. Wrapper scripts additionally back up stale state before fresh sessions.

The vendored fork retains upstream GPL-3.0 licensing. AEiOU wrapper/scripts outside the vendor tree are MIT-licensed.

## Important warning

Bootloader unlocking changes the device security state. Depending on device/firmware, unlocking can trigger data loss or make a device unbootable if interrupted or misused. Back up important data first. Use this only on devices you own or are authorized to modify.

## Quick start

Open an **Administrator PowerShell** in this repository:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1
```

Install UsbDk and a MediaTek CDC/ACM driver if `setup.ps1` reports either missing.

Recommended read-only hardware gate:

```powershell
.\preflight.ps1
```

For BROM entry on the verified Redmi Note 10 5G:

1. Disconnect USB and power the phone fully off.
2. Hold **Power + Volume Up + Volume Down**.
3. Connect USB.
4. On the Windows USB-connect sound, immediately release all three buttons.
5. Press nothing while mtkclient runs.

`preflight.ps1` must reach BROM, DRAM setup, DA stage 2, and GPT enumeration before it reports PASS.
Then power-cycle the phone and run a fresh unlock session:

```powershell
.\unlock.ps1
```

The wrapper only accepts success when mtkclient exits with code `0` **and** emits explicit upstream evidence such as `Device is already unlocked` or `Successfully wrote seccfg.`. It never trusts an unconditional wrapper message.

Afterward, reboot to Fastboot (Power + Volume Down) and verify:

```powershell
.\verify.ps1
```

If your bootloader exposes the variable, the expected result is `unlocked: yes`.

## Why this wrapper exists

A stale mtkclient `.state` file can make a new process treat a fresh connection as an existing DA session. On MT6833 this reproduced as:

```text
GET_RAM_INFO
struct.error: unpack requires a buffer of 12 bytes
```

This toolkit backs up stale state before every hardware session and never assumes a DA session survives across separate mtkclient processes.

## More documentation

- [Technical flow](docs/TECHNICAL.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Verified device record](docs/VERIFIED-DEVICE.md)
- [Upstream/credits](docs/CREDITS.md)

## License

AEiOU wrapper code is MIT-licensed. The bundled `vendor/mtkclient` fork is derived from bkerler/mtkclient and remains GPL-3.0; see `vendor/mtkclient/LICENSE` and `vendor/mtkclient/AEIOU_FORK.md`.

## End-to-end LineageOS + GApps + Magisk workflow

The repository now also contains a guarded continuation path for the hardware-verified Redmi Note 10 5G profile:

```powershell
.\install-all.ps1 -Manifest .\config\verified-camellia.json `
  -ArtifactsRoot 'C:\path\to\verified-artifacts' `
  -AcknowledgeDataLoss
```

Stages are `preflight -> unlock -> verify -> rom -> gapps -> root -> postflight`. Use `-FromStage`, `-ToStage`, or `-Resume` when continuing an interrupted workflow. Use `-WhatIf` to print the complete requested stage plan without requiring a connected phone or writing workflow state.

The verified manifest pins SHA-256 values for the exact LineageOS 23.2 build, its `boot.img`, the matching MindTheGapps Android 16 arm64 package, and the official stable Magisk APK used for the verified path. Large binaries are intentionally not stored in Git.

Automation stops at physical boundaries that cannot be performed safely over USB: fresh BROM entry, recovery Format Data confirmation, recovery ADB-sideload selection, normal Android setup/USB authorization, and the first Magisk Superuser approval. The PC-side transfer, hash validation, slot validation, flashing, sideload, boot polling, and postflight checks are automated around those gates.

`rom-install.ps1` is destructive and requires `-AcknowledgeDataLoss`. All mutation stages fail closed on hash/profile/slot/unlock errors. `root-magisk.ps1` patches only the exact ROM boot image and never substitutes a foreign boot image.

See [Root, updates, and recovery](docs/ROOT-AND-UPDATES.md) for OTA/root behavior and the original-boot fallback.
### Root completion gate

After the Magisk reboot on Android 16, unlock the device normally once before opening Magisk. The final postflight does not treat `magiskd` alone as proof of usable root: it also requires `su -c id` to return `uid=0(root)` after the Shell policy is approved in Magisk Superuser.
