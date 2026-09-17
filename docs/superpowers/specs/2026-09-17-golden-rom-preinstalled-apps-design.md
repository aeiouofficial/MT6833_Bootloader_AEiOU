# Golden ROM Preinstalled Apps Design

## Goal

Make the currently installed utility/security app set survive a normal Android factory reset without USB, ADB, a PC restore step, Play Store, or network access during the restore itself.

## Verified device constraints

- Device family: Redmi Note 10 5G / camellia / MT6833.
- Current ROM: LineageOS 23.2 / Android 16.
- Current slot: `_a`.
- Bootloader state: unlocked (`ro.boot.verifiedbootstate=orange`).
- Runtime verity state: disabled (`ro.boot.veritymode=disabled`).
- Dynamic partitions: `system_a`, `system_ext_a`, `vendor_a`, `product_a` in `mediatek_dynamic_partitions_a`.
- `product_a` is ext4 and currently has about 466 MiB free, enough for the app payload.
- Existing MindTheGapps state must be preserved exactly; therefore the source for the golden product image is the **live current `product_a` block image**, not the pristine Lineage OTA `product.img`.

## Golden app baseline

The golden product image contains the exact APK bytes currently installed on the phone for these packages:

- `com.topjohnwu.magisk` — Magisk Manager 30.7
- `dev.imranr.obtainium` — Obtainium 1.6.17
- `com.machiav3lli.backup` — Neo Backup 8.3.18
- `com.termux` — Termux 0.119.0-beta.3
- `io.github.muntashirakon.AppManager` — App Manager 4.1.1
- `com.celzero.bravedns` — Rethink DNS + Firewall v0.5.6
- `ch.protonvpn.android` — Proton VPN 5.20.21.0
- `duress.keyboard` — DuressKeyboard 7.4

The APKs are placed as ordinary system applications under `/product/app/AEiOU_<Name>/<Name>.apk`; they are **not** privileged apps and are not re-signed.

## Why the live product partition is the authority

MindTheGapps was installed after the base Lineage OTA. Rebuilding from the original OTA product partition would discard current product-side GApps changes. Capturing the live logical partition preserves the exact current ROM/GApps product state and changes only the addition of the eight system APKs.

## Filesystem mutation

The builder captures `product_a` to a raw image, duplicates it to a candidate, then modifies only the candidate with Linux `debugfs`/`e2fsprogs` through WSL2. New directories are root-owned mode `0755`; APKs are root-owned mode `0644`. Both directories and APK files receive `security.selinux=u:object_r:system_file:s0`, matching Android 16 product file contexts.

The builder must fail if:

- the connected profile/slot is not the expected camellia MT6833 post-ROM state;
- root is unavailable for the partition capture;
- any expected package/version is missing;
- any package resolves to split APKs instead of one standalone base APK;
- total APK bytes plus a safety margin exceed free product filesystem space;
- the source or candidate ext4 filesystem fails `e2fsck` validation;
- any embedded APK hash differs from the captured APK hash;
- any expected `/app/AEiOU_*` path or SELinux xattr is missing after mutation.

## Flash/install model

The first installation of the golden image is a one-time operation. The flash script:

1. verifies candidate SHA-256 and manifest;
2. verifies device profile, active slot, unlocked bootloader and `veritymode=disabled`;
3. keeps the untouched captured product image as the local rollback artifact;
4. enters userspace fastboot (`fastbootd`);
5. flashes only `product_<active-slot>`;
6. reboots Android;
7. verifies boot completion, SELinux Enforcing, Magisk daemon/root and presence of all eight `/product/app/AEiOU_*` APKs.

No factory reset is performed during build/flash verification.

## Factory-reset semantics

A normal factory reset wipes userdata. It does not rewrite `product_a` or the patched Magisk boot image. Therefore after the reset:

- all eight golden APKs are discovered again as system apps from `/product/app`;
- the Magisk boot patch remains present, and the preinstalled Magisk Manager app returns;
- app data, accounts, permissions, VPN sessions, Termux home files and other userdata do **not** survive;
- DuressKeyboard returns only as an installed app. Device Admin, default IME, wipe command, failed-password limits and other destructive triggers are never baked into the image.

## OTA boundary

A later Lineage OTA can replace the product partition and therefore remove the golden app baseline. The repository must document that the golden product image is persistent across factory reset, not across arbitrary OTA replacement. Rebuilding/reapplying the golden product layer is required after a ROM OTA that rewrites product.

## Safety

- Never relock the bootloader.
- Never flash or weaken vbmeta in this feature.
- Never format userdata.
- Never arm DuressKeyboard automatically.
- Keep the original captured product image outside Git and hash it for rollback.
- Do not commit APKs or partition images to the public repository.
