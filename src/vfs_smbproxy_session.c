/*
 * Per-tree SMB1 backend sessions for the smb-proxy appliance.
 *
 * Samba calls connect_fn once for every downstream tree connection.  The
 * connection carries the authenticated SMB session id (vuid) and tree id
 * (cnum), so this is the first point where the appliance can create an exact
 * downstream-to-upstream mapping without guessing from usernames or PIDs.
 *
 * The helper mounts the legacy share with a distinct CIFS superblock and SMB1
 * socket. Samba then operates directly on that mount. The standard fileid VFS
 * module must follow this module in smb.conf so Samba maps those superblocks
 * back to one share-wide locking identity. With posix locking = yes and no
 * `nobrl` option, byte-range locks are also sent to the SMB1 server.
 */

#include "includes.h"
#include "smbd/smbd.h"
#include "lib/util/tevent_unix.h"

#define MODULE_NAME "smbproxy_session"
#define MOUNT_HELPER "/usr/local/sbin/smbproxy-session-mount"
#define SMBPROXY_READ_CHUNK_SIZE 16384

struct smbproxy_session_state {
	char *service;
	char *mountpoint;
	struct tevent_queue *pread_queue;
	pid_t pid;
	uint64_t vuid;
	uint32_t cnum;
};

static void smbproxy_session_state_free(void **data)
{
	TALLOC_FREE(*data);
}

static int smbproxy_run_helper(const char *action,
			       const struct smbproxy_session_state *state)
{
	char *service = NULL;
	char *command = NULL;
	int ret;

	service = escape_shell_string(state->service);
	if (service == NULL) {
		errno = ENOMEM;
		return -1;
	}

	command = talloc_asprintf(talloc_tos(),
		"%s %s %s %ld %" PRIu64 " %" PRIu32,
		MOUNT_HELPER,
		action,
		service,
		(long)state->pid,
		state->vuid,
		state->cnum);
	SAFE_FREE(service);
	if (command == NULL) {
		errno = ENOMEM;
		return -1;
	}

	/* The service is shell-escaped; action is a fixed module literal and the
	 * remaining fields are decimal integers. The hook runs during Samba's
	 * root connect/disconnect phase because it owns the CIFS lifecycle. */
	ret = smbrun_no_sanitize(command, NULL, NULL);
	TALLOC_FREE(command);
	if (ret != 0) {
		errno = EIO;
		return -1;
	}
	return 0;
}

static int smbproxy_session_connect(vfs_handle_struct *handle,
				    const char *service,
				    const char *user)
{
	struct smbproxy_session_state *state = NULL;
	int ret;

	state = talloc_zero(handle->conn, struct smbproxy_session_state);
	if (state == NULL) {
		errno = ENOMEM;
		return -1;
	}

	state->pid = getpid();
	state->vuid = handle->conn->vuid;
	state->cnum = handle->conn->cnum;
	state->service = talloc_strdup(state, service);
	state->mountpoint = talloc_asprintf(state,
		"/run/smbproxy/sessions/%ld-%" PRIu64 "-%" PRIu32,
		(long)state->pid,
		state->vuid,
		state->cnum);
	state->pread_queue = tevent_queue_create(state,
		"smbproxy_session_pread");
	if (state->service == NULL || state->mountpoint == NULL ||
	    state->pread_queue == NULL) {
		TALLOC_FREE(state);
		errno = ENOMEM;
		return -1;
	}

	if (smbproxy_run_helper("connect", state) != 0) {
		DBG_ERR("failed to create SMB1 session for [%s], vuid=%" PRIu64
			", cnum=%" PRIu32 "\n",
			service, state->vuid, state->cnum);
		TALLOC_FREE(state);
		return -1;
	}

	if (!set_conn_connectpath(handle->conn, state->mountpoint)) {
		DBG_ERR("failed to set connect path to %s\n", state->mountpoint);
		(void)smbproxy_run_helper("disconnect", state);
		TALLOC_FREE(state);
		errno = ENOMEM;
		return -1;
	}

	SMB_VFS_HANDLE_SET_DATA(handle,
		state,
		smbproxy_session_state_free,
		struct smbproxy_session_state,
		return -1);

	ret = SMB_VFS_NEXT_CONNECT(handle, service, user);
	if (ret != 0) {
		(void)smbproxy_run_helper("disconnect", state);
		SMB_VFS_HANDLE_FREE_DATA(handle);
	}
	return ret;
}

static void smbproxy_session_disconnect(vfs_handle_struct *handle)
{
	struct smbproxy_session_state *state = NULL;

	SMB_VFS_HANDLE_GET_DATA(handle,
		state,
		struct smbproxy_session_state,
		SMB_VFS_NEXT_DISCONNECT(handle); return);

	SMB_VFS_NEXT_DISCONNECT(handle);
	if (smbproxy_run_helper("disconnect", state) != 0) {
		DBG_ERR("failed to release SMB1 session for [%s], vuid=%" PRIu64
			", cnum=%" PRIu32 "\n",
			state->service, state->vuid, state->cnum);
	}
	SMB_VFS_HANDLE_FREE_DATA(handle);
}

/*
 * The Windows Server 2008 SP2 SMB1 server used by the appliance returns
 * signatures that Linux rejects when one pread is split into concurrent
 * READ_ANDX requests. Keep each request within the classic 16 KiB SMB1
 * buffer and issue the chunks sequentially. This changes only transfer
 * shape; opens, sessions, share modes, and byte-range locks are untouched.
 */
static ssize_t smbproxy_session_pread(vfs_handle_struct *handle,
				      files_struct *fsp,
				      void *data,
				      size_t n,
				      off_t offset)
{
	uint8_t *buf = data;
	size_t done = 0;

	while (done < n) {
		size_t chunk = MIN(n - done, SMBPROXY_READ_CHUNK_SIZE);
		ssize_t ret = SMB_VFS_NEXT_PREAD(handle,
						 fsp,
						 buf + done,
						 chunk,
						 offset + done);

		if (ret < 0) {
			return -1;
		}
		done += ret;
		if ((size_t)ret < chunk) {
			break;
		}
	}

	return done;
}

struct smbproxy_session_pread_state {
	struct tevent_context *ev;
	vfs_handle_struct *handle;
	files_struct *fsp;
	struct tevent_req *queue_req;
	uint8_t *data;
	size_t n;
	size_t done;
	size_t chunk;
	off_t offset;
	struct vfs_aio_state vfs_aio_state;
};

static void smbproxy_session_pread_queued(struct tevent_req *queue_req);
static void smbproxy_session_pread_done(struct tevent_req *subreq);

static void smbproxy_session_pread_release_queue(
	struct smbproxy_session_pread_state *state)
{
	if (state->queue_req == NULL) {
		return;
	}
	(void)tevent_queue_wait_recv(state->queue_req);
	TALLOC_FREE(state->queue_req);
}

static bool smbproxy_session_pread_next(struct tevent_req *req)
{
	struct smbproxy_session_pread_state *state = tevent_req_data(
		req, struct smbproxy_session_pread_state);
	struct tevent_req *subreq = NULL;

	state->chunk = MIN(state->n - state->done,
			   SMBPROXY_READ_CHUNK_SIZE);
	subreq = SMB_VFS_NEXT_PREAD_SEND(state,
					  state->ev,
					  state->handle,
					  state->fsp,
					  state->data + state->done,
					  state->chunk,
					  state->offset + state->done);
	if (tevent_req_nomem(subreq, req)) {
		return false;
	}
	tevent_req_set_callback(subreq, smbproxy_session_pread_done, req);
	return true;
}

static struct tevent_req *smbproxy_session_pread_send(
	struct vfs_handle_struct *handle,
	TALLOC_CTX *mem_ctx,
	struct tevent_context *ev,
	struct files_struct *fsp,
	void *data,
	size_t n,
	off_t offset)
{
	struct tevent_req *req = NULL;
	struct smbproxy_session_pread_state *state = NULL;
	struct smbproxy_session_state *session = NULL;

	req = tevent_req_create(mem_ctx,
				&state,
				struct smbproxy_session_pread_state);
	if (req == NULL) {
		return NULL;
	}
	SMB_VFS_HANDLE_GET_DATA(handle,
		session,
		struct smbproxy_session_state,
		tevent_req_error(req, EIO);
		return tevent_req_post(req, ev));

	state->ev = ev;
	state->handle = handle;
	state->fsp = fsp;
	state->data = data;
	state->n = n;
	state->offset = offset;

	if (n == 0) {
		tevent_req_done(req);
		return tevent_req_post(req, ev);
	}

	state->queue_req = tevent_queue_wait_send(state,
						  ev,
						  session->pread_queue);
	if (tevent_req_nomem(state->queue_req, req)) {
		return tevent_req_post(req, ev);
	}
	tevent_req_set_callback(state->queue_req,
				smbproxy_session_pread_queued,
				req);
	return req;
}

static void smbproxy_session_pread_queued(struct tevent_req *queue_req)
{
	struct tevent_req *req = tevent_req_callback_data(
		queue_req, struct tevent_req);
	struct smbproxy_session_pread_state *state = tevent_req_data(
		req, struct smbproxy_session_pread_state);
	int error;

	if (tevent_req_is_unix_error(queue_req, &error)) {
		smbproxy_session_pread_release_queue(state);
		tevent_req_error(req, error);
		return;
	}

	if (!smbproxy_session_pread_next(req)) {
		smbproxy_session_pread_release_queue(state);
	}
}

static void smbproxy_session_pread_done(struct tevent_req *subreq)
{
	struct tevent_req *req = tevent_req_callback_data(
		subreq, struct tevent_req);
	struct smbproxy_session_pread_state *state = tevent_req_data(
		req, struct smbproxy_session_pread_state);
	struct vfs_aio_state chunk_state = { 0 };
	ssize_t ret;

	ret = SMB_VFS_PREAD_RECV(subreq, &chunk_state);
	TALLOC_FREE(subreq);
	if (ret < 0) {
		smbproxy_session_pread_release_queue(state);
		tevent_req_error(req,
			chunk_state.error != 0 ? chunk_state.error : EIO);
		return;
	}

	state->vfs_aio_state = chunk_state;
	state->done += ret;
	if ((size_t)ret < state->chunk || state->done == state->n) {
		smbproxy_session_pread_release_queue(state);
		tevent_req_done(req);
		return;
	}

	if (!smbproxy_session_pread_next(req)) {
		smbproxy_session_pread_release_queue(state);
	}
}

static ssize_t smbproxy_session_pread_recv(
	struct tevent_req *req,
	struct vfs_aio_state *vfs_aio_state)
{
	struct smbproxy_session_pread_state *state = tevent_req_data(
		req, struct smbproxy_session_pread_state);

	if (tevent_req_is_unix_error(req, &vfs_aio_state->error)) {
		return -1;
	}
	*vfs_aio_state = state->vfs_aio_state;
	return state->done;
}

static struct vfs_fn_pointers smbproxy_session_fns = {
	.connect_fn = smbproxy_session_connect,
	.disconnect_fn = smbproxy_session_disconnect,
	.pread_fn = smbproxy_session_pread,
	.pread_send_fn = smbproxy_session_pread_send,
	.pread_recv_fn = smbproxy_session_pread_recv,
};

static_decl_vfs;
NTSTATUS vfs_smbproxy_session_init(TALLOC_CTX *ctx);
NTSTATUS vfs_smbproxy_session_init(TALLOC_CTX *ctx)
{
	return smb_register_vfs(SMB_VFS_INTERFACE_VERSION,
				MODULE_NAME,
				&smbproxy_session_fns);
}
