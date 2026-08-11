# Agent Guide

This repository owns `vfs_smbproxy_session`, a private Samba `source3` VFS
module used by the sibling SMB proxy appliance. Read
[`../dev-commons/CONTEXT.md`](../dev-commons/CONTEXT.md) and
[`../dev-commons/STYLE.md`](../dev-commons/STYLE.md) before substantive work.

## Non-negotiable contracts

- A release artifact is compatible with exactly one Debian `samba` binary
  package revision. Never weaken the exact dependency or the runtime guard.
- `connect_fn` derives identity from Samba's real `vuid`, `cnum`, and worker
  PID. Do not substitute a username, client address, or inferred process key.
- The module creates no locks. It redirects a tree connection to the
  appliance-owned per-tree CIFS mount. The appliance must chain Samba's
  standard `fileid` module with `fileid:algorithm = fsname` so distinct CIFS
  superblocks share one Samba locking identity.
- The module invokes `/usr/local/sbin/smbproxy-session-mount`; that helper and
  its credentials are deliberately outside this repository.
- SMB1 interoperability observations are evidence, not guarantees. Record the
  server/client release, dialect, signing mode, kernel, Samba package, and a
  reproducer in `docs/KNOWN-ISSUES.md`.

## Success gate

Run `scripts/check.sh`. A publish candidate additionally requires the exact
Samba build workflow plus the sibling appliance's `tps-lock-isolation` lab
scenario described in `docs/MAINTENANCE.md`.

## Repository boundary

The source module, build/package tooling, compatibility ledger, and upstream
tracking automation live here. Appliance runtime policy, mounting, UI,
credentials, image creation, and production deployment live in
`../smb-proxy-appliance`.
