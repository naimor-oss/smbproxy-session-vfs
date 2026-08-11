# Upstream Sources and Watch List

Use primary sources for maintenance decisions. Search results and third-party
summaries can locate material but do not become release evidence.

| Surface | Primary source | What to watch |
| --- | --- | --- |
| Debian Trixie Samba binary | <https://packages.debian.org/trixie/samba> | Exact binary revision, dependencies, security/update pocket. |
| Debian Samba source | <https://sources.debian.org/src/samba/> | Matching source revision and Debian patches. |
| Debian package tracker | <https://tracker.debian.org/pkg/samba> | New uploads, bugs, security migrations. |
| Samba release notes | <https://www.samba.org/samba/history/> | VFS, smbd, locking, share modes, SMB1 and signing changes. |
| Samba `vfs_fileid` manual | <https://www.samba.org/samba/docs/current/man-html/vfs_fileid.8.html> | File identity algorithms and lock-coherency warnings. |
| Samba bugs | <https://bugzilla.samba.org/> | Regressions matching a reproducible trace. |
| Linux CIFS documentation | <https://docs.kernel.org/admin-guide/cifs/usage.html> | SMB1 mount support, locking, signing, reconnect, and mount options. |
| Linux SMB client source | <https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/fs/smb/client> | Behavior not fully documented in the admin guide. |
| `cifs-utils` source | <https://git.samba.org/?p=cifs-utils.git> | `mount.cifs` option parsing and credential handling. |
| Microsoft [MS-CIFS] | <https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cifs/69a29f73-de0c-45bf-8ff2-0f9d8c9b805a> | Base dialect, locking, signing, errors, and Windows behavior notes. |
| Microsoft [MS-SMB] | <https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-smb/f210069c-7086-4dc2-885e-861d837df688> | SMB 1.0 extensions and revision diffs. |

## Review cadence

- GitHub Actions checks the Trixie Samba candidate weekly and on demand.
- Review Debian/Samba notes whenever the candidate changes, even if the module
  still compiles.
- Review Linux CIFS changes whenever the appliance kernel changes; this module
  cannot compensate for a client locking/signing regression.
- Revisit Microsoft SMB1 behavior only when adding a supported server/client
  release or investigating a reproducible interop difference.
