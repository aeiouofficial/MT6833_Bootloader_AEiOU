# Credits and upstream

This toolkit includes a bundled AEiOU fork of the upstream **mtkclient** project by Bjoern Kerler and contributors, plus AEiOU wrapper scripts and documentation:

- Project: `bkerler/mtkclient`
- Upstream license: GNU GPL v3
- Verified/pinned revision: `cd25cf9c1ff6d36e82697ac2c798e69e9cfb78c3`

The original community guide that motivated the workflow was published on XDA Developers under the title **Instant Bootloader Unlock Without Losing Data** for POCO M3 Pro 5G / Redmi Note 10 5G devices.

This repository does not claim authorship of upstream mtkclient, its MediaTek exploitation techniques, its DA loaders, or the original XDA procedure. The bundled fork preserves upstream attribution and GPL-3.0 licensing; AEiOU-specific changes are documented in `vendor/mtkclient/AEIOU_FORK.md`.

## Dependency boundaries

`vendor/mtkclient` contains the exact verified upstream snapshot plus AEiOU stale-state hardening. `setup.ps1` uses this bundled fork directly instead of cloning another copy.

The AEiOU wrapper is MIT-licensed. The bundled `vendor/mtkclient` source and loaders remain under upstream GPL-3.0 license terms.
