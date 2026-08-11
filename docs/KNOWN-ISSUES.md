# Known Issues and Compatibility Ledger

This file separates established constraints from observations that still need
packet-level proof. Do not turn a resemblance to an upstream bug into a root
cause without a trace and reproducer.

## Accepted baseline

| Item | Value | Evidence |
| --- | --- | --- |
| Component | `0.1.0`, source SHA-256 `e107384ad375721c84dc33391bf01d19f6f75cb35a347be67706abab782dae46` | Matches the source and deployed metadata inspected 2026-08-07. |
| Debian Samba | `2:4.22.10+dfsg-0+deb13u2` | Running appliance and `compatibility/trixie.env`. |
| Architecture | `amd64` | Running appliance. |
| End-to-end status | Real multi-user Clarion TopSpeed application reports shared user/seat state after the per-tree-session fix. | Operator acceptance, followed by live health inspection. |

The baseline is operational evidence for this environment, not a general claim
about every SMB1 server or Windows release.

## SAMBA-ABI-001 — private source3 VFS ABI

**Status:** permanent constraint.

The module reads connection fields and changes the connection path through
Samba-private `source3` interfaces. Debian's public development surface is not
sufficient for this build. Even when upstream's numeric VFS interface version
does not change, a Debian patch revision is not assumed binary-compatible.

**Control:** build from the exact Debian Samba source revision, package with an
exact Samba dependency, and retain the runtime package-version guard.

## SAMBA-FILEID-001 — distinct mounts split default file identity

**Status:** controlled by required configuration.

Per-tree CIFS mounts have different device identities. Without Samba's standard
`fileid` VFS module, identical backend inodes can occupy separate Samba
share-mode/locking namespaces.

**Control:** `vfs objects = smbproxy_session fileid` and
`fileid:algorithm = fsname`. Never use the `nolock` fileid algorithms here;
Samba explicitly warns that they break SMB semantics and can cause corruption.

## SMB1-LOCK-001 — backend byte-range lock forwarding is mount-policy dependent

**Status:** controlled by the sibling appliance.

The custom module creates session boundaries; it does not issue SMB1 lock
requests. Linux CIFS must forward byte-range locks. `nobrl` would make locks
local to the appliance and violate the product guarantee. Oplocks are disabled
for legacy database shares to avoid cache semantics that the application does
not expect.

**Control:** inspect the live mount options and run the two-session upstream
lock-conflict gate for every release.

## SMB1-SIGN-001 — intermittent SMB1 READ_ANDX signature verification errors

**Status:** reproduced; component mitigation under qualification.

The production backend is Windows Server 2008 SP2 x86 build `6.0.6002` with
`srv.sys` `6.0.6002.18005`, SMB2 disabled, and SMB1 signing required. Against
Linux CIFS `2.51` on Debian kernels `6.12.86` and `6.12.101`, one application
read larger than the negotiated SMB1 read size is split into multiple signed
`SMB_COM_READ_ANDX` requests. Linux rejects responses with error `-13`; the
frontend receives `ENOMEM` ("Cannot allocate memory") even though the appliance
has ample free memory.

The 2026-08-10 reproducer used a static 2,897,578-byte file and the production
mount policy (`vers=1.0`, `cache=none`, `hard`, `nosharesock`, `rsize=61440`,
`wsize=16384`). Reads of 61,440 bytes or less completed with the expected hash;
a 65,536-byte read failed. With smaller mount `rsize` values, an application
read exactly equal to that size passed while a larger split read failed. A
packet trace and kernel timestamps correlated the failure with the split read.

Component `0.2.0` mitigates the defect by serializing frontend reads into
16-KiB backend `pread` operations. This changes transfer shape only: opens,
sessions, share modes, and byte-range locks continue through the normal VFS and
CIFS paths. It is not accepted until the exact-Samba build, downstream large
copy, two-session lock gate, and real ProfitFab test all pass.

The exact-Samba amd64 package was installed on the production proxy on
2026-08-10. The package/version guard, configuration hash comparison, service
restart, and immediate kernel-log check passed; `smbd` was stopped at 14:34:14
PDT and started at 14:34:15 PDT. Downstream copy and application acceptance
remain pending, so the accepted-baseline table above intentionally stays at
component `0.1.0`.

Do not disable required signing or enable permissive signature handling as an
undocumented workaround. Updating the legacy server remains desirable because
its SMB server binary predates later Server 2008 SP2 servicing by many years.
Samba bug 14484 describes the same Linux error for an SMB1 READ_ANDX signature
layout defect, but it is retained as a similar upstream report rather than
claimed as proof of the exact Windows defect here.

**Reference:** <https://bugzilla.samba.org/show_bug.cgi?id=14484>

## Adding an issue

Use a durable ID and record:

- affected client/server OS and patch level;
- Samba Debian package, Linux kernel, `cifs-utils`, and architecture;
- negotiated dialect, transport, signing requirement, and authentication;
- minimal reproducer and expected versus actual lock/open result;
- packet trace or log locations with secrets removed;
- workaround, security tradeoff, and release-gate impact.
