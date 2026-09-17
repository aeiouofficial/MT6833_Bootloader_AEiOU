# MT6833 Bootloader Toolkit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish a tested Windows PowerShell toolkit that pins the verified mtkclient revision, prevents stale-state failures, performs a read-only DA gate, unlocks only via `seccfg`, and verifies evidence.

**Architecture:** Shared pure guard/evidence functions live in `src/Toolkit.psm1`; executable entry points are thin scripts. Tests run without a phone and validate state backup, chipset/evidence parsing, destructive-command exclusion, and script wiring. GitHub Actions runs the same tests on Windows.

**Tech Stack:** PowerShell 5.1+, Git, Python 3.8+, upstream mtkclient 2.1.4 pinned to `cd25cf9c1ff6d36e82697ac2c798e69e9cfb78c3`, GitHub Actions Windows runner.

**Spec:** `docs/superpowers/specs/2026-09-17-mt6833-bootloader-toolkit-design.md`

## Global Constraints
- No erase/format/wipe commands.
- No unlock success claim without exit code 0 and explicit mtkclient evidence.
- Back up `.state`; never silently delete it.
- Fail closed when MT6833 evidence is missing.
- Do not publish device-unique identifiers.

---

### Task 1: Shared safety/evidence module
- [ ] Write failing tests for stale-state backup, MT6833 detection, read-only gate evidence, and unlock evidence.
- [ ] Run tests and confirm RED because `src/Toolkit.psm1` does not exist.
- [ ] Implement minimal module functions.
- [ ] Re-run tests and confirm GREEN.

### Task 2: Setup, preflight, unlock, verify entry points
- [ ] Add failing static/integration tests for required scripts and destructive-command exclusion.
- [ ] Confirm RED.
- [ ] Implement scripts using the shared module.
- [ ] Confirm GREEN.

### Task 3: Public docs and CI
- [ ] Add README, technical/troubleshooting/verified-device docs, MIT license, `.gitignore`, and Windows CI.
- [ ] Run repository tests and syntax checks.
- [ ] Scan repository for unique device IDs and destructive commands.
- [ ] Commit and push to `main`.
