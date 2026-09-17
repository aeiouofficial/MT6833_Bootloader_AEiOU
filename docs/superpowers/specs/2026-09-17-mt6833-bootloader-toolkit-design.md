# MT6833 Bootloader Toolkit Design

**Date:** 2026-09-17

## Goal
Provide a reproducible Windows-first wrapper around upstream `bkerler/mtkclient` for MT6833 bootloader unlocking, based on a verified Redmi Note 10 5G (M2103K19G / camellian_eea) success.

## Architecture
The repository does not vendor mtkclient. `setup.ps1` clones and pins upstream commit `cd25cf9c1ff6d36e82697ac2c798e69e9cfb78c3`, creates a CLI virtual environment, and installs only CLI dependencies. Shared guard/evidence logic lives in `src/Toolkit.psm1`. `preflight.ps1` performs a read-only `printgpt` DA gate. `unlock.ps1` always starts from a fresh BROM session, backs up stale `.state`, and runs only `da seccfg unlock`. `verify.ps1` checks Fastboot when available and can validate mtkclient evidence logs.

## Safety invariants
- Never erase, format, wipe, or flash arbitrary partitions.
- Never claim success from wrapper text alone.
- Accept success only from exit code 0 plus explicit mtkclient unlock evidence.
- Back up stale `.state` instead of deleting it.
- Fail closed if MT6833 evidence is absent.
- Do not publish ME_ID, SOC_ID, Android serials, or other unique device identifiers.
- Read-only GPT gating is a separate process/session and never assumed reusable for unlock.

## Verified target
Redmi Note 10 5G model M2103K19G, codename `camellian`, EEA product `camellian_eea`, SoC MT6833 / Dimensity 700, UFS `MT128GASAO4U21`, MIUI `V14.0.4.0.TKSEUXM`.

## Licensing
Wrapper code is MIT. mtkclient is fetched from upstream and remains GPL-3.0 under its own license.
