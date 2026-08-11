# Handoff Notes

Start with:

- [`README.md`](README.md) for the repository and release contract.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the lock-coherency design.
- [`docs/MAINTENANCE.md`](docs/MAINTENANCE.md) for Samba update qualification.
- [`docs/KNOWN-ISSUES.md`](docs/KNOWN-ISSUES.md) for the maintained issue ledger.
- [`compatibility/trixie.env`](compatibility/trixie.env) for the accepted Debian
  Trixie Samba package revision.

The sibling `smb-proxy-appliance` owns the privileged mount helper, share
configuration, runtime guard, and end-to-end tests. This repository owns only
the Samba-private VFS source and artifacts built from it.
