# SMB Proxy Session VFS

`vfs_smbproxy_session` gives each downstream Samba tree connection its own
upstream SMB1 CIFS mount and socket. It exists to preserve per-session behavior
when the sibling [`smb-proxy-appliance`](../smb-proxy-appliance/) publishes a
legacy share to modern SMB clients.

This is a Samba component, not an appliance component. It uses Samba-private
`source3` structures (`vuid`, `cnum`, and connection path mutation), so every
binary release is built for and depends on one exact Debian `samba` package
revision. The component version describes this source; the artifact version
also carries the Samba build target and CPU architecture.

## Where do I start?

| If you want to … | Read / run |
| --- | --- |
| Understand why separate upstream sessions still need one lock namespace | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Qualify a new Debian Samba revision | [`docs/MAINTENANCE.md`](docs/MAINTENANCE.md) |
| Review known Samba, Linux CIFS, and SMB1 interoperability risks | [`docs/KNOWN-ISSUES.md`](docs/KNOWN-ISSUES.md) |
| Check Windows/SMB1 behavior by release family | [`docs/SMB1-COMPATIBILITY.md`](docs/SMB1-COMPATIBILITY.md) |
| Build a package on Debian 13 | `sudo scripts/build-debian-package.sh` |
| Run fast local checks | `scripts/check.sh` |
| Find upstream specifications and trackers | [`docs/UPSTREAM-SOURCES.md`](docs/UPSTREAM-SOURCES.md) |

## Release contract

The generated package:

- installs `smbproxy_session.so` into the `MODULESDIR` reported by the target
  `smbd`;
- declares `Depends: samba (= <exact Debian revision>)`;
- records component version, exact Samba revision, and source hash under
  `/usr/share/smbproxy-session-vfs/`;
- is architecture-specific even though the C source is portable.

An old component package therefore holds Samba at the last qualified revision.
The scheduled workflow detects a new Trixie candidate, builds it as evidence,
and opens one qualification issue. It does not advance
[`compatibility/trixie.env`](compatibility/trixie.env) or publish a production
update without the appliance lock-integrity gate.

## Build

Use a disposable Debian 13 builder with binary and source repositories enabled:

```bash
sudo scripts/build-debian-package.sh \
    --samba-version '2:4.22.10+dfsg-0+deb13u2' \
    --output-dir dist
```

The script installs exact build dependencies, obtains the matching Debian
source package, invokes Debian's own Samba configure target, builds only this
module, and emits a `.deb` plus a checksum/provenance manifest.

For appliance image preparation, `scripts/export-appliance-payload.sh` exports
the minimal source/build payload. The appliance owns the privileged mount
helper and installs the resulting package during image construction.

## Repository map

| Path | Purpose |
| --- | --- |
| `src/` | Canonical VFS C source. |
| `scripts/build-debian-package.sh` | Exact-revision Samba source build and `.deb` packaging. |
| `scripts/build-and-install.sh` | Image-builder wrapper for building and installing the matching package. |
| `compatibility/trixie.env` | Accepted Trixie Samba revision and tested architectures. |
| `.github/workflows/trixie-samba.yml` | Scheduled candidate detection and compatibility build. |
| `.github/workflows/publish-apt.yml` | Tag-triggered signed APT repository publication to GitHub Pages. |
| `tests/` | Fast source and packaging contract checks. |
| `docs/` | Architecture, compatibility, issues, maintenance, and upstream sources. |

## Scope boundary

This repository deliberately does not contain credentials, CIFS mount policy,
Samba share configuration, appliance UI, or a promise that every SMB1 server
implements identical locking behavior. Those belong to the appliance and its
lab evidence. The hard guarantee is fail-closed compatibility with the exact
Samba package and a release gate that proves the required lock behavior against
the actual legacy backend.
