# Experimental Deployment Path

## Recommended near-term path

Do not block on a perfect FFU first.

Use this sequence instead:

1. Boot `Mu-alioth-1.img` through fastboot.
2. Enter `Mass Storage Mode` in UEFI.
3. Expose the phone storage to Windows.
4. Apply `install.wim` to the `WIN` partition with `DISM`.
5. Write boot files to `ESP` with `bcdboot`.
6. If driver packs become available, inject them offline with `DriverUpdater`.
7. Attempt first boot.
8. If it fails, collect offline logs from the `WIN` partition and iterate.

## Why this path is preferable right now

- It avoids needing a finalized alioth FFU profile before first experiments.
- It works with the files already on disk:
  - `install.wim`
  - `Mu-alioth-1.img`
  - `DriverUpdater`
- It aligns with how alioth community installs are commonly staged:
  repartition first, then deploy Windows manually.

## Current blockers

- The phone is not currently visible in usable `adb` or `fastboot`.
- We still do not have a public alioth Windows driver payload.
- `DISM` requires an elevated shell on this PC.
