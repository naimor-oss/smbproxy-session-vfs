# Maintenance and Release Qualification

## Version model

There are three independent identities:

- **Component version** (`VERSION`): source and contract changes in this repo.
- **Samba package revision** (`compatibility/trixie.env`): the exact Debian
  binary/source package used for a build.
- **Architecture**: the Debian architecture of the binary module.

A component source version may produce several artifacts. For example, the
same `0.1.0` source can be rebuilt for a Trixie security update without
pretending the appliance itself changed. The generated Debian package version
encodes both component and Samba versions and has an exact Samba dependency.

## Automated Trixie tracking

The scheduled GitHub workflow performs a cheap detection job against fresh
Debian Trixie repositories. If the candidate differs from the accepted value:

1. it builds the module against that exact candidate;
2. uploads the `.deb` and provenance manifest as workflow evidence;
3. opens one issue naming the old and new revisions and linking the run.

The workflow intentionally does not edit `compatibility/trixie.env`, tag a
release, or publish to the appliance update source. A successful compile only
proves build compatibility.

## Qualification checklist

For a new Trixie Samba revision:

1. Review the Debian changelog, Debian security tracker, and upstream Samba
   release notes for VFS, file serving, share-mode, signing, and SMB1 changes.
2. Build with `scripts/build-debian-package.sh --samba-version <revision>`.
3. Inspect the package:
   - exact `Depends: samba (= <revision>)`;
   - expected `MODULESDIR/vfs/smbproxy_session.so`;
   - matching component, Samba, and source-hash metadata.
4. Build a fresh sibling appliance image using that artifact.
5. Run the appliance's fast checks and prepared-image smoke scenario.
6. Run `tps-lock-isolation` against the real staging backend. It must prove:
   - two authenticated downstream trees create distinct live CIFS mounts;
   - the mounts have distinct CIFS filesystem identities;
   - overlapping open/share modes are denied coherently;
   - upstream byte-range lock conflicts are visible between sessions;
   - reconnect and disconnect remove transient mounts.
7. Exercise the real Clarion TopSpeed application with at least two users.
   Confirm its seat/user record is shared, simultaneous edits are serialized,
   and a client exit leaves no stale seat or mount.
8. Copy a file larger than 64 KiB through the downstream SMB3 share and verify
   its hash. Confirm the operation adds no CIFS signature errors to the kernel
   log; a direct read of the backend mount does not exercise the VFS shim.
9. Check kernel logs for new CIFS signing, reconnect, lock, or I/O errors.
10. Record the tested Samba revision, Debian kernel, architecture, legacy server
   release, signing policy, and result in `docs/KNOWN-ISSUES.md` or a dated
   test record.
11. Advance `compatibility/trixie.env`, publish the rebuilt component artifact,
    then update the appliance component pin. Dependency first, consumer second.

## Custom appliance update source

The tag- or manually-triggered `publish-apt.yml` workflow builds the accepted
revision, retains packages from the current feed, creates a signed static APT
repository, and deploys it to GitHub Pages. Before
the first tag, configure repository secrets `APT_SIGNING_KEY_B64` (the exported
secret key, base64 encoded) and `APT_SIGNING_KEY_FINGERPRINT`, then enable Pages
with GitHub Actions as its source. The intended source is:

```deb822
Types: deb
URIs: https://naimor-oss.github.io/smbproxy-session-vfs
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/smbproxy-session-vfs-archive-keyring.gpg
```

Release tags are `v<component-version>` or
`v<component-version>-<build-label>` when unchanged component source is rebuilt
for a later Samba revision. The workflow publishes the public key at the
repository root. Bootstrap must
verify its full fingerprint out of band before installing it under
`/usr/share/keyrings`; HTTPS download alone is not key verification. The
workflow carries forward packages listed by the existing amd64 feed so the APT
source retains rollback candidates.

Until the signed feed and fingerprint are configured, appliance image builds
consume the hash-verified source payload from this sibling repository. Do not
enable unattended Samba upgrades without a matching component feed: the exact
package dependency is expected to hold Samba at the last qualified revision.


## Source-change checklist

Any C change also requires:

- `scripts/check.sh`;
- builds against the accepted Trixie revision and current Trixie candidate;
- review of the module/helper argument contract;
- the full lock-integrity and real-application gates above;
- a component version bump and updated source hash in the appliance pin.
