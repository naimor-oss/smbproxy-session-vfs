# SMB1 and Windows Compatibility Notes

“SMB1” is not one uniform wire behavior. Older SMB dialects are negotiated from
a list that can include Core, LAN Manager variants, and `NT LM 0.12` (CIFS).
Microsoft's SMB 1.0 extensions apply only after `NT LM 0.12` is selected. Lock
commands, extended information levels, Unicode, large-file support, oplocks,
authentication, and signing therefore vary with the negotiated dialect and
capabilities—not just the marketing name of the operating system.

## Release-family tracking matrix

| Windows family | SMB relevance to this project | Qualification posture |
| --- | --- | --- |
| Windows 9x / DOS / early LAN Manager clients | May negotiate pre-NT dialects with reduced capabilities and different error mappings. | Unsupported until captured and tested explicitly; never assume `NT LM 0.12`. |
| Windows NT 4.0 / 2000 / XP / Server 2003 | SMB1/CIFS is the primary file protocol. Signing, Unicode, oplock, and authentication policy vary by release and service pack. | Record exact OS/service pack and negotiated flags for every supported backend. |
| Vista / Server 2008 and Windows 7 / Server 2008 R2 | SMB2 was introduced, but SMB1 remained available for legacy negotiation. | Force and verify the backend dialect; do not infer SMB1 merely from server age. |
| Windows 8 / Server 2012 through early Windows 10 / Server 2016 | SMB3-era systems can retain an optional SMB1 stack. Defaults and security policy increasingly discourage it. | Treat SMB1 enablement and signing policy as explicit server configuration. |
| Windows 10 1709+ / Server 2019+ / Windows 11 | SMB1 is deprecated and absent by default on many clean installations; client and server features may be removed separately. | Not a proxy backend assumption. Use only as controlled compatibility fixtures. |

The table is a test-routing guide, not a claim that every edition or patch
level behaves identically. Microsoft documents edition- and upgrade-specific
SMB1 removal behavior, including the Windows 10 1803/1809 difference.

## Behavior that must be measured

For a new legacy server or Windows release, record:

- dialect identifier selected (`NT LM 0.12` versus an older dialect);
- server capability and flags, especially Unicode, large files, NT status,
  extended security, oplocks, and signing supported/required;
- authentication type and whether signing is actually active;
- open/share-mode conflict results across two sessions;
- byte-range lock conflict, unlock, close, disconnect, and reconnect behavior;
- delete/rename behavior while another session has the file open;
- application behavior under simultaneous record access.

## Known release-sensitive areas

- **Signing:** negotiation can fail when one side requires signing and the
  other does not support it. The qualified Server 2008 SP2 backend also
  triggers Linux signature rejection when a large frontend read is split into
  multiple signed SMB1 READ_ANDX requests. The component serializes reads into
  16-KiB requests as a narrowly scoped interoperability control; see
  `SMB1-SIGN-001`.
- **Oplocks:** SMB1 oplocks are not SMB3 leases. The legacy database profile
  disables frontend oplocks and must verify the backend did not reintroduce
  unsafe caching.
- **Error mapping:** DOS/LAN Manager dialects and NT-status-capable dialects can
  report the same lock conflict differently. Tests should assert behavior, not
  only one numeric error.
- **Disconnect cleanup:** old servers differ in how quickly abandoned locks
  disappear. Test abrupt client death as well as clean close.
- **SMB1 availability:** modern Windows patch and installation history affects
  whether SMB1 binaries exist; the OS name alone is insufficient.

## Authoritative protocol references

- Microsoft [MS-CIFS] version and capability negotiation:
  <https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cifs/80850595-e301-4464-9745-58e4945eb99b>
- Microsoft [MS-SMB] SMB 1.0 extensions:
  <https://learn.microsoft.com/en-us/openspecs/windows_protocols/MS-SMB/fd2a8346-9414-40e2-81b1-ed294f9768ea>
- Microsoft SMB1 installation/removal behavior:
  <https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/smbv1-not-installed-by-default-in-windows>
