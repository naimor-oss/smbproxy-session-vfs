# Architecture and Lock-Coherency Contract

## Problem

One long-lived CIFS mount collapses every downstream user onto one upstream
SMB1 session. That is unsafe for a multi-user ISAM application because the
legacy server no longer observes independent client sessions. The module moves
mount creation to Samba's tree-connect lifecycle, where the authenticated
`vuid` and tree `cnum` are available.

For each downstream tree connection the module:

1. captures the Samba worker PID, `vuid`, `cnum`, and service name;
2. asks `/usr/local/sbin/smbproxy-session-mount` to create a distinct CIFS
   mount at `/run/smbproxy/sessions/<pid>-<vuid>-<cnum>`;
3. redirects that Samba connection to the new mount;
4. calls the next VFS connect hook;
5. disconnects and releases the mount when the tree ends.

For reads, the module also serializes each frontend request into 16-KiB backend
operations. This avoids a reproduced signed-SMB1 READ_ANDX split failure on the
qualified Windows Server 2008 SP2 backend. The read shim does not alter open,
share-mode, session, or byte-range-lock handling.

The appliance helper mounts with SMB1 and a distinct socket/superblock. It does
not use `nosharesock` alone as session identity; the per-tree mount lifecycle is
the identity boundary.

## Two lock namespaces must remain coherent

The split introduces two layers that have different jobs:

| Layer | Authority | Required behavior |
| --- | --- | --- |
| Samba frontend | Downstream open/share modes and Samba-local coordination | Every mount of the same backend file must map to one Samba `file_id`. |
| Linux CIFS / SMB1 backend | Byte-range lock operations seen by the legacy server | Each tree uses its own SMB1 session and forwards locks; `nobrl` is forbidden. |

Distinct CIFS mounts normally return distinct device IDs. Samba's default file
identity includes device and inode, which would split its share-mode database
and let two downstream clients open what Samba thinks are different files.
Therefore the appliance must configure:

```ini
vfs objects = smbproxy_session fileid
fileid:algorithm = fsname
strict locking = yes
posix locking = yes
oplocks = no
level2 oplocks = no
```

Samba documents that `file_id` is used for locking and that the `fsname`
algorithm hashes the kernel filesystem name. The standard `fileid` module is
load-bearing here; `smbproxy_session` must precede it in the VFS chain.

## What the module does not guarantee

- It does not implement or emulate SMB1 record locking.
- It does not turn SMB3 leases into SMB1 oplocks; the appliance disables
  oplocks for these shares.
- It cannot generally correct a legacy server's nonconforming signing,
  locking, or close behavior. The read shim is limited to the one reproduced
  signing interoperability defect documented as `SMB1-SIGN-001`.
- It cannot make different Windows SMB1 implementations identical.

The component guarantees an exact downstream-tree-to-upstream-session mapping
and fails closed on Samba package mismatch. The sibling appliance's lab tests
establish the end-to-end locking behavior for each supported backend.

## Security boundary

The module runs inside `smbd` and invokes one fixed absolute helper path during
root connect/disconnect processing. The service name is shell-escaped; the
action is a module literal and the remaining arguments are integers. Keep the
helper root-owned and non-writable by the Samba service identity. Any change to
the invocation contract needs source review and an appliance integration test.
