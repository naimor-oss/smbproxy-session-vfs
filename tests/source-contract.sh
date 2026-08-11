#!/usr/bin/env bash
# Static assertions for the session identity and module-registration boundary.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VFS="$ROOT/src/vfs_smbproxy_session.c"

for required in \
    '#include "lib/util/tevent_unix.h"' \
    'handle->conn->vuid' \
    'handle->conn->cnum' \
    'state->pid = getpid()' \
    'set_conn_connectpath(handle->conn, state->mountpoint)' \
    'smbproxy_run_helper("connect", state)' \
    'smbproxy_run_helper("disconnect", state)' \
    'tevent_queue_create(state' \
    'tevent_queue_wait_send(state' \
    'tevent_queue_wait_recv(state->queue_req)' \
    '#define SMBPROXY_READ_CHUNK_SIZE 16384' \
    'SMB_VFS_NEXT_PREAD(handle' \
    'SMB_VFS_NEXT_PREAD_SEND(state' \
    'smbproxy_session_pread_recv' \
    '.pread_fn = smbproxy_session_pread' \
    '.pread_send_fn = smbproxy_session_pread_send' \
    '.pread_recv_fn = smbproxy_session_pread_recv' \
    'static_decl_vfs;' \
    'vfs_smbproxy_session_init'; do
    grep -qF "$required" "$VFS" || {
        echo "FAIL VFS contract missing: $required" >&2
        exit 1
    }
done

grep -qF '#define MOUNT_HELPER "/usr/local/sbin/smbproxy-session-mount"' "$VFS"
echo "source contract passed"
