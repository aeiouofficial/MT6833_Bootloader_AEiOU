# Golden ROM Preinstalled Apps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and safely install a golden `product_a` image that contains the current eight utility/security APKs as ordinary `/product/app` system apps so they return automatically after a factory reset.

**Architecture:** Capture the live rooted `product_a` partition and exact installed standalone APK bytes, mutate only a copy of the ext4 image through WSL2/e2fsprogs, verify hashes/xattrs/filesystem integrity, and flash only the active product logical partition through fastbootd. Repository scripts contain logic/tests/docs; multi-gigabyte images and APKs stay local and are referenced by SHA-256 manifests.

**Tech Stack:** PowerShell 5+, ADB/Fastboot platform-tools, Python 3, WSL2 Ubuntu 22.04, e2fsprogs/debugfs, SHA-256, GitHub Actions Windows CI.

**Spec:** `docs/superpowers/specs/2026-09-17-golden-rom-preinstalled-apps-design.md`

## Global Constraints

- Device must match post-ROM MT6833/camellia profile.
- Active slot must be detected dynamically and remain unchanged.
- `ro.boot.verifiedbootstate` must be `orange` and `ro.boot.veritymode` must be `disabled` before flashing.
- Never relock bootloader, modify vbmeta, format userdata, or arm DuressKeyboard.
- Source product image is captured from the live current logical product partition so current MindTheGapps changes are preserved.
- Golden app APK bytes are captured from the currently installed packages and must be standalone single APKs.
- Binaries/images/APKs are local artifacts and must not be committed.

---

### Task 1: Golden manifest and contract tests

**Files:**
- Create: `config/golden-rom-apps.json`
- Create: `tests/test-golden-rom.ps1`

**Interfaces:**
- Consumes: existing `src/Workflow.psm1` device/hash helpers.
- Produces: ordered package/version/name contract used by capture/build/flash scripts.

- [ ] Write a failing test requiring exactly eight package entries, safe product paths, explicit expected versions, and forbidden destructive tokens.
- [ ] Run the test and confirm RED because the manifest/scripts do not exist.
- [ ] Add `config/golden-rom-apps.json` with the eight exact package/version pairs from the design spec.
- [ ] Re-run the contract portion and keep script-existence assertions RED until Tasks 2-4.
- [ ] Commit.

### Task 2: Capture current product and exact APK bytes

**Files:**
- Create: `golden-rom-capture.ps1`
- Modify: `tests/test-golden-rom.ps1`

**Interfaces:**
- Input: `-OutputRoot`, optional `-AdbPath`, `-Manifest`.
- Output: `source-product.img`, `apps/*.apk`, `capture-manifest.json` with SHA-256/size/version/package/sourcePath/slot/device metadata.

- [ ] Add fake-ADB tests for profile mismatch, missing root, split APK rejection, exact version mismatch, binary-safe product capture command, APK hash recording, and no userdata mutation.
- [ ] Verify RED.
- [ ] Implement capture using Python subprocess streaming for binary-safe `adb exec-out su -c cat <block>` and APK capture; resolve package paths with `pm path`; require exactly one APK path per package.
- [ ] Verify captured product size against `lpdump` extent size and run SHA-256.
- [ ] Run targeted tests GREEN.
- [ ] Commit.

### Task 3: Build ext4 golden product image

**Files:**
- Create: `golden-rom-build.ps1`
- Create: `scripts/golden-product-build.sh`
- Modify: `tests/test-golden-rom.ps1`

**Interfaces:**
- Input: capture directory from Task 2.
- Output: `golden-product.img`, `golden-product-manifest.json`.

- [ ] Add hardware-free fixture test using a small ext4 image created in WSL; require eight app paths, modes, uid/gid and `security.selinux` xattr plus clean `e2fsck`.
- [ ] Verify RED.
- [ ] Implement WSL preflight for `debugfs`, `e2fsck`, `tune2fs`; fail with actionable package requirement if unavailable.
- [ ] Copy source image to candidate and verify source filesystem clean/readable.
- [ ] Use a debugfs command file to create `/app/AEiOU_<safe-name>`, write each APK, set uid/gid 0, directory mode 0755, APK mode 0644, and SELinux xattr `u:object_r:system_file:s0`.
- [ ] Run `e2fsck -fn` after mutation; verify each embedded file by dumping it back and comparing SHA-256 to captured APK hash.
- [ ] Require at least 64 MiB free product space after mutation.
- [ ] Write candidate manifest with source/candidate/APK hashes.
- [ ] Run targeted tests GREEN.
- [ ] Commit.

### Task 4: One-time golden product flash and postflight

**Files:**
- Create: `golden-rom-flash.ps1`
- Modify: `tests/test-golden-rom.ps1`

**Interfaces:**
- Input: `golden-product-manifest.json`, candidate image, ADB/Fastboot paths, explicit `-AcknowledgeProductFlash`.
- Output: verified booted device or automatic rollback attempt using `source-product.img` if the candidate fails to boot.

- [ ] Add fake ADB/Fastboot tests requiring exact candidate hash, unlocked/orange/verity-disabled gates, `adb reboot fastboot`, userspace-fastboot gate, flash of only `product_<slot>`, no vbmeta/format/slot-change commands, reboot and postflight checks.
- [ ] Verify RED.
- [ ] Implement gates and dry-run/WhatIf support.
- [ ] Flash only active `product_<slot>` and reboot.
- [ ] Verify Android boot completion, SELinux Enforcing, `magiskd`, `su -c id`, all eight `/product/app/AEiOU_*` APK files and package versions.
- [ ] On boot/postflight failure, document and attempt rollback by flashing the captured original product image; never format userdata.
- [ ] Run targeted tests GREEN.
- [ ] Commit.

### Task 5: End-to-end documentation and CI

**Files:**
- Create: `docs/GOLDEN-ROM.md`
- Modify: `.gitignore`
- Modify: `.github/workflows/windows-ci.yml` only if the existing test discovery does not already include the new tests.

**Interfaces:**
- Documents capture → build → flash → factory-reset semantics and rollback.

- [ ] Document that factory reset restores app installation baseline but not app data/accounts/permissions/Termux home/Duress configuration.
- [ ] Document that ROM OTAs may overwrite product and require rebuilding/reapplying the golden layer.
- [ ] Ignore local golden image/APK/manifests under the default artifact directory.
- [ ] Run parser checks and the full repository test suite.
- [ ] Build a real candidate from the connected phone and verify the generated manifest/hashes/filesystem before any flash.
- [ ] Flash candidate, reboot, run postflight, and retain original product image for rollback.
- [ ] Open PR, require GitHub Actions GREEN, merge, verify main CI, delete temporary checkout.
