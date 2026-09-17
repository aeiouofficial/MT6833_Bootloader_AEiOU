# AEiOU mtkclient fork

Base project: `bkerler/mtkclient`
Base revision: `cd25cf9c1ff6d36e82697ac2c798e69e9cfb78c3` (2026-09-12)
Upstream version: `2.1.4`
Upstream license: GNU GPL v3 (see `LICENSE` in this directory).

This directory is the exact source snapshot used for the verified MT6833 unlock workflow, plus AEiOU-specific hardening.

## AEiOU change

`mtkclient/Library/DA/mtk_da_handler.py` no longer automatically reuses persisted `.state` merely because a USB connection is present. The verified MT6833 failure showed that stale state can incorrectly drive `daloader.reinit()` and fail at `GET_RAM_INFO` with a short/empty status header.

Automatic state reinit is therefore disabled by default in this fork. Advanced users can explicitly opt back into upstream behavior by setting:

`MTKCLIENT_ALLOW_STATE_REINIT=1`

The wrapper scripts also back up `.state` before fresh hardware sessions.