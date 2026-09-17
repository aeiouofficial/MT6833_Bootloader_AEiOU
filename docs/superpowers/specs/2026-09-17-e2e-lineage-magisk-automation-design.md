# End-to-End Lineage + Magisk Automation Design

## Goal

Extend the existing Windows-first MT6833 bootloader toolkit into a guarded, resumable workflow that can take the verified Redmi Note 10 5G / MT6833 path from preflight through bootloader verification, LineageOS installation, GApps installation, Magisk root, and postflight QA.

## Verified target

The hardware-verified profile is the Xiaomi Redmi Note 10 5G (`M2103K19G`, stock codename `camellian`, MT6833). The currently verified custom-ROM target is LineageOS 23.2 / Android 16 using the camellia build family. The verified boot image has Android boot header v2, a real boot ramdisk, A/B `boot_a` / `boot_b`, `vendor_boot_a` / `vendor_boot_b`, no `init_boot`, and no separate recovery partition. Initial root uses the latest stable official Magisk GitHub release, currently v30.7.

## Safety model

The orchestrator is fail-closed. It must never continue after an unexpected device identity, missing tool, missing or mismatched artifact hash, failed command, unknown active slot, locked bootloader, failed sideload, failed boot, or failed root verification. Destructive operations require an explicit acknowledgement switch and a matching device profile. The workflow must not relock the bootloader, write `vbmeta` merely to obtain root, disable verity by default, format arbitrary partitions, or flash a boot image from another ROM build.

## Architecture

`src/Toolkit.psm1` remains the shared library. New focused helpers cover external command execution, ADB/Fastboot state detection, artifact manifests and hashes, device-profile gates, resumable state, sideload result parsing, Magisk release metadata, and postflight assertions. Thin top-level entrypoints invoke these helpers and remain readable.

The user-facing stages are:

1. `preflight.ps1` - existing MTK/BROM read-only gate.
2. `unlock.ps1` - existing mtkclient unlock gate.
3. `verify.ps1` - existing Fastboot unlock verification.
4. `rom-install.ps1` - verify profile/artifacts, flash the exact recovery-bearing `boot.img`, reboot recovery, require the destructive format acknowledgement, and guide/verify ROM sideload.
5. `gapps-install.ps1` - verify recovery sideload mode and sideload the exact GApps artifact.
6. `root-magisk.ps1` - obtain and verify official stable Magisk, install the APK, patch the exact ROM `boot.img` on the connected device, pull and validate the patched image, flash only the active `boot_<slot>`, reboot, and verify root.
7. `postflight.ps1` - verify boot, root, SELinux, encryption, slot/AVB state, GApps, storage, USB, radio stack, Wi-Fi/Bluetooth/NFC, camera providers, sensors, audio, thermal state, and crash buffers without collecting private media or location.
8. `install-all.ps1` - orchestrate stages with durable state, explicit destructive gates, and resume support.

## Artifact contract

ROM, recovery-bearing `boot.img`, GApps, and optional Magisk release metadata are described by a JSON manifest. The workflow compares SHA-256 before every write/sideload. It must retain the original ROM `boot.img` unchanged and record its hash. Generated `magisk_patched-*.img` is stored separately and never replaces the source image.

## Magisk contract

Use only the official `topjohnwu/Magisk` GitHub stable release. The release asset digest must match the downloaded APK. The image-patching operation must run on the target Android device, using the exact boot image belonging to the installed ROM build. On the verified target, flash only the current active boot slot. Root success requires an operational Magisk daemon and `su -c id` returning `uid=0(root)`. SELinux must remain `Enforcing`.

## State and resume

Each successful stage writes an atomic JSON state record under `.aeiou-state/` with stage name, timestamp, device serial, product/model, active slot when relevant, artifact hashes, command exit evidence, and next stage. A rerun validates that recorded facts still match the connected device before resuming. State may skip completed read-only work but must never bypass a destructive gate after device identity changes.

## Interactive boundaries

Physical BROM entry and recovery UI actions that Android does not expose safely remain explicit human interaction points. The orchestrator waits for and verifies the resulting USB state instead of pretending those actions can be performed remotely. ADB sideload itself and all PC-side transfers are automated.

## Testing

Unit-style PowerShell tests cover parsers, profile gates, slot normalization, artifact hashing, sideload success/failure recognition, stage transitions, resume invalidation, and command construction. Entrypoint tests require `-WhatIf` / dry-run behavior that performs no device writes. Existing public-safety tests are extended to reject bootloader relock, arbitrary partition format, default vbmeta disablement, and flashing without hash/profile gates.

A hardware smoke test is separate from normal CI and runs only with an explicitly connected authorized device. It records evidence but does not make CI depend on hardware.

## Documentation

README and technical docs document the verified hardware, exact destructive steps, data-loss warning, recovery interaction boundaries, root/update implications, and how Lineage updates can replace the boot partition and therefore require patching the new build's boot image again. No bundled ROM/GApps/Magisk binaries are committed; manifests and download metadata are text-only.