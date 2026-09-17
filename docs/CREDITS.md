# Credits and upstream

This toolkit is a thin wrapper around the upstream **mtkclient** project by Bjoern Kerler and contributors:

- Project: `bkerler/mtkclient`
- Upstream license: GNU GPL v3
- Verified/pinned revision: `cd25cf9c1ff6d36e82697ac2c798e69e9cfb78c3`

The original community guide that motivated the workflow was published on XDA Developers under the title **Instant Bootloader Unlock Without Losing Data** for POCO M3 Pro 5G / Redmi Note 10 5G devices.

This repository does not claim authorship of mtkclient, its MediaTek exploitation techniques, its DA loaders, or the original XDA procedure. AEiOU-specific work here is limited to the reproducible wrapper, state-safety guards, tests, and documentation derived from hardware debugging on the verified device.

## Dependency boundaries

`setup.ps1` fetches mtkclient directly from its upstream Git repository and checks out the pinned commit. No mtkclient source or binaries are copied into this repository.

The AEiOU wrapper is MIT-licensed. Files fetched from upstream remain under their upstream license terms.
