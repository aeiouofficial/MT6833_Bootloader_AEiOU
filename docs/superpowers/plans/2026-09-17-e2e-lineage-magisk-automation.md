# End-to-End Lineage + Magisk Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a guarded, resumable Windows PowerShell workflow from MT6833 unlock verification through LineageOS, GApps, Magisk root, and postflight QA.

**Architecture:** Keep the existing unlock toolkit intact, add a focused workflow module for Android/Fastboot/artifact/state logic, and expose thin stage entrypoints plus one orchestrator. All destructive actions are profile/hash/slot gated; tests run in dry-run fixtures while hardware smoke remains opt-in.

**Tech Stack:** Windows PowerShell 5.1+, ADB/Fastboot platform-tools, mtkclient, JSON manifests/state, official GitHub release metadata.

**Spec:** `docs/superpowers/specs/2026-09-17-e2e-lineage-magisk-automation-design.md`

## Global Constraints

- Verified target profile: Redmi Note 10 5G MT6833, stock identity `M2103K19G` / `camellian`, custom-ROM identity may report `M2103K19C` / `camellia` only after the ROM stage.
- Fail closed on unknown identity, hash mismatch, unknown slot, command failure, or missing evidence.
- Never relock the bootloader, never format arbitrary partitions, and never disable vbmeta/verity by default.
- Root patches the exact installed ROM `boot.img` on the target device and flashes only the active `boot_<slot>`.
- No ROM, GApps, or Magisk binaries are committed.

---

### Task 1: Workflow primitives and profile gates

**Files:**
- Create: `src/Workflow.psm1`
- Create: `tests/test-workflow.ps1`
- Modify: `tests/run-all.ps1`

**Interfaces:**
- Produces: `Invoke-CheckedCommand`, `Get-DeviceState`, `Normalize-Slot`, `Test-DeviceProfile`, `Get-Sha256`, `Assert-ArtifactHash`.

- [ ] Write tests first for slot normalization (`_a`, `a`, `_b`, `b`), profile acceptance/rejection, hash match/mismatch, and nonzero-command failure.
- [ ] Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test-workflow.ps1` and confirm RED because `src/Workflow.psm1` does not exist.
- [ ] Implement only the tested helpers; command wrapper returns stdout/stderr/exit code and throws on nonzero unless explicitly allowed.
- [ ] Re-run the new test and full `tests/run-all.ps1`; require all PASS.
- [ ] Commit `test/workflow primitives` plus implementation.

### Task 2: Manifest and resumable state contract

**Files:**
- Create: `config/verified-camellia.json`
- Modify: `src/Workflow.psm1`
- Create: `tests/test-state.ps1`
- Modify: `tests/run-all.ps1`

**Interfaces:**
- Produces: `Read-WorkflowManifest`, `Read-WorkflowState`, `Write-WorkflowState`, `Assert-ResumeCompatible`.

- [ ] Write RED tests using temporary JSON fixtures for valid manifest, missing SHA-256, atomic state write, stage transition, and resume rejection after serial/product/slot change.
- [ ] Implement manifest validation and atomic state replacement under `.aeiou-state/`.
- [ ] Re-run focused and full tests to GREEN.
- [ ] Commit manifest/state support.

### Task 3: ROM and GApps stage entrypoints

**Files:**
- Create: `rom-install.ps1`
- Create: `gapps-install.ps1`
- Create: `tests/test-rom-gapps.ps1`
- Modify: `tests/test-public-safety.ps1`
- Modify: `tests/run-all.ps1`

**Interfaces:**
- Consumes: manifest/profile/hash/device-state helpers.
- Produces: stage scripts supporting `-Manifest`, `-ArtifactsRoot`, `-WhatIf`; ROM stage additionally requires `-AcknowledgeDataLoss` before format guidance.

- [ ] Write RED tests that inspect dry-run command plans and prove no flash/sideload occurs without correct profile/hash and destructive acknowledgement.
- [ ] Implement Fastboot unlock gate, exact `boot_<slot>` selection, recovery reboot, sideload-state verification, and strict `adb sideload` exit parsing.
- [ ] Extend public-safety test to reject `fastboot flashing lock`, arbitrary `format`, and default `--disable-verity/--disable-verification` strings.
- [ ] Run focused/full tests GREEN.
- [ ] Commit ROM/GApps stages.

### Task 4: Official Magisk acquisition and device-side patch pipeline

**Files:**
- Create: `root-magisk.ps1`
- Create: `tests/test-root-magisk.ps1`
- Modify: `src/Workflow.psm1`
- Modify: `tests/run-all.ps1`

**Interfaces:**
- Produces: `Get-LatestStableMagiskRelease`, `Assert-MagiskReleaseAsset`, `New-MagiskPatchPlan`, `Test-RootEvidence`.

- [ ] Write RED tests with saved GitHub-release JSON fixtures covering stable-vs-prerelease selection, asset digest verification, no `init_boot` fallback on this profile, active-slot flash construction, and root evidence (`uid=0(root)`, Magisk daemon present, SELinux `Enforcing`).
- [ ] Implement release metadata parsing and download digest gate; allow an explicit pinned version/digest in manifest for reproducibility.
- [ ] Implement device-side boot patch flow: install official APK, push exact source `boot.img`, run the official Magisk patch operation on the target, pull generated image, confirm it differs from source and remains a valid Android boot image, reboot fastboot, flash only active boot slot, reboot Android.
- [ ] Verify root and SELinux before writing stage success state.
- [ ] Run focused/full tests GREEN.
- [ ] Commit Magisk root stage.

### Task 5: Postflight QA

**Files:**
- Create: `postflight.ps1`
- Create: `tests/test-postflight.ps1`
- Modify: `tests/run-all.ps1`

**Interfaces:**
- Produces: a structured JSON/console report with PASS/FAIL/SKIP checks.

- [ ] Write RED parser tests for boot completion, encryption, SELinux, GApps package paths, root, storage RW, USB configured, SIM/radio state, Wi-Fi/Bluetooth/NFC services, camera count/errors, sensors, audio underruns/errors, thermal status, and crash/ANR buffers.
- [ ] Implement read-only checks; radio toggles are opt-in and restore original state in `finally`.
- [ ] Exclude microphone recording, camera captures, NFC payment transactions, and precise GNSS location from automated QA.
- [ ] Run focused/full tests GREEN.
- [ ] Commit postflight QA.

### Task 6: Install-all orchestrator

**Files:**
- Create: `install-all.ps1`
- Create: `tests/test-install-all.ps1`
- Modify: `tests/test-entrypoints.ps1`
- Modify: `tests/run-all.ps1`

**Interfaces:**
- Consumes all stage entrypoints and `.aeiou-state`.
- Produces: `-FromStage`, `-ToStage`, `-Resume`, `-WhatIf`, `-AcknowledgeDataLoss` orchestration.

- [ ] Write RED tests for ordered stages, stop-on-failure, resume from valid state, invalid-resume rejection, and dry-run with zero device writes.
- [ ] Implement stage dispatch without bypassing individual stage gates.
- [ ] Run focused/full tests GREEN.
- [ ] Commit orchestrator.

### Task 7: Documentation and CI/static safety

**Files:**
- Modify: `README.md`
- Modify: `docs/TECHNICAL.md`
- Modify: `docs/TROUBLESHOOTING.md`
- Create: `docs/ROOT-AND-UPDATES.md`
- Modify or create: `.github/workflows/test.yml`

**Interfaces:**
- Documents the exact verified path and keeps CI hardware-free.

- [ ] Add documentation for data loss, recovery interaction boundaries, artifact hashes, Magisk update behavior, Lineage OTA replacing boot, and recovery fallback using the untouched original `boot.img`.
- [ ] Ensure CI runs `tests/run-all.ps1` only; hardware smoke remains an explicit local operation.
- [ ] Run full tests and syntax parsing for every `.ps1`/`.psm1`.
- [ ] Commit docs/CI.

### Task 8: Hardware verification on the authorized connected device

**Files:**
- Runtime evidence only; do not commit private device identifiers or generated boot images.

**Interfaces:**
- Executes `root-magisk.ps1` against the already-installed verified Lineage build, then `postflight.ps1`.

- [ ] Record source boot SHA-256 and official Magisk release/digest.
- [ ] Patch source boot on device, pull patched image, validate Android boot magic and source/patched hash difference.
- [ ] Flash only the active slot, reboot, require `sys.boot_completed=1`.
- [ ] Require `su -c id` -> `uid=0(root)`, Magisk daemon present, and SELinux `Enforcing`.
- [ ] Run postflight; require no blocking failures.
- [ ] Re-run repository full tests after hardware-derived adjustments.
- [ ] Push verified branch, inspect diff/CI, and open a PR to `main` rather than silently merging unreviewed destructive automation.