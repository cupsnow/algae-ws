/**
 * @author joelai
 */

#include "priv.h"

#define log_m(_lvl, _fmt, _args...) printf(_lvl "%s #%d " _fmt, __func__, __LINE__, ##_args)
#define log_e(_args...) log_m("ERRORs ", ##_args)
#define log_d(_args...) log_m("Debug ", ##_args)

 /** Minimal due time for select(), value in micro-seconds. */
#define ALOE_EV_PREVENT_BUSY_WAITING 1001ul

static aloe_ev_ctx_fd_t* fd_q_find(aloe_ev_ctx_fd_queue_t *q, int fd, char pop) {
	aloe_ev_ctx_fd_t *ev_fd;

	if (fd == -1) {
		if ((ev_fd = TAILQ_FIRST(q)) && pop) {
			TAILQ_REMOVE(q, ev_fd, qent);
		}
		return ev_fd;
	}

	TAILQ_FOREACH(ev_fd, q, qent) {
		if (ev_fd->fd == fd) return ev_fd;
	}
	return NULL;
}

static aloe_ev_ctx_noti_t* noti_q_find(aloe_ev_ctx_noti_queue_t *q,
		const aloe_ev_ctx_noti_t *_ev_noti, char pop) {
	aloe_ev_ctx_noti_t *ev_noti;

	if (!_ev_noti) {
		if ((ev_noti = TAILQ_FIRST(q)) && pop) {
			TAILQ_REMOVE(q, ev_noti, qent);
		}
		return ev_noti;
	}

	TAILQ_FOREACH(ev_noti, q, qent) {
		if (ev_noti == _ev_noti) return ev_noti;
	}
	return NULL;
}

int aloe_local_socket_address(struct sockaddr_un *sa, socklen_t *sa_len,
		const char *path) {
	size_t path_size = strlen(path);

	if (path_size >= sizeof(sa->sun_path)) {
		log_e("Too long for local socket address\n");
		return -1;
	}
	memset(sa, 0, sizeof(*sa));
	sa->sun_family = AF_UNIX;
	memcpy(sa->sun_path, path, path_size);
	if (sa_len) *sa_len = aloe_offsetof(struct sockaddr_un, sun_path) + path_size + 1;
	return 0;
}

int aloe_local_socker_listener(const char *path, int backlog,
		struct sockaddr_un *sa, socklen_t *sa_len) {
	int fd = -1, r;
	struct sockaddr_un _sa;
	socklen_t _sa_len;

	if (!sa || !sa_len) {
		if (!sa) sa = &_sa;
		sa_len = &_sa_len;
	}
	if ((fd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
		r = errno;
		log_e("%s (AF_UNIX) socket, %s(%d)\n", path, strerror(r), r);
		goto finally;
	}
	if ((r = aloe_local_socket_address(sa, sa_len, path)) != 0) {
		goto finally;
	}
	unlink(path);
	if (bind(fd, (struct sockaddr*)sa, *sa_len) < 0) {
		r = errno;
		log_e("%s (AF_UNIX) bind, %s(%d)\n", path, strerror(r), r);
		goto finally;
	}
	if (listen(fd, backlog) < 0) {
		r = errno;
		log_e("%s (AF_UNIX) listen, %s(%d)\n", path, strerror(r), r);
		goto finally;
	}
finally:
	if (r != 0) {
		if (fd != -1) close(fd);
		return -1;
	}
	return fd;
}

int aloe_file_nonblock(int fd, int en) {
	int r;

	if ((r = fcntl(fd, F_GETFL, NULL)) == -1) {
		r = errno;
		log_e("Failed to get file flag: %s(%d)\n", strerror(r), r);
		return r;
	}
	if (en) r |= O_NONBLOCK;
	else r &= (~O_NONBLOCK);
	if ((r = fcntl(fd, F_SETFL, r)) != 0) {
		r = errno;
		log_e("Failed to set nonblocking file flag: %s(%d)\n", strerror(r), r);
		return r;
	}
	return 0;
}

void* aloe_ev_put(void *_ctx, int fd, aloe_ev_noti_cb_t cb, void *cbarg,
		unsigned ev_wait, unsigned long sec, unsigned long usec) {
	aloe_ev_ctx_t *ctx = (aloe_ev_ctx_t*)_ctx;
	aloe_ev_ctx_fd_t *ev_fd;
	aloe_ev_ctx_noti_t *ev_noti;
	struct timespec due;
	struct {
		unsigned ev_fd_inq: 1;
		unsigned ev_noti_inq: 1;
	} flag = {0};

	if (sec == ALOE_EV_INFINITE) {
		due.tv_sec = ALOE_EV_INFINITE;
	} else {
		if ((clock_gettime(CLOCK_MONOTONIC, &due)) != 0) {
			int r = errno;
			log_e("monotonic timestamp: %s(%d)\n", strerror(r), r);
			return NULL;
		}
		ALOE_TIMESEC_ADD(due.tv_sec, due.tv_nsec, sec, usec * 1000ul,
		        due.tv_sec, due.tv_nsec, 1000000000ul);
	}

	if ((ev_fd = fd_q_find(&ctx->fd_q, fd, 0))) {
		flag.ev_fd_inq = 1;
	} else if (!(ev_fd = fd_q_find(&ctx->spare_fd_q, -1, 1)) && !(ev_fd =
	        malloc(sizeof(*ev_fd)))) {
		log_e("malloc ev_fd\n");
		return NULL;
	}

	if ((ev_noti = noti_q_find(&ctx->spare_noti_q, NULL, 1))) {
		flag.ev_noti_inq = 1;
	} else if (!(ev_noti = malloc(sizeof(*ev_noti)))) {
		log_e("malloc ev_noti\n");
		if (!flag.ev_fd_inq) {
			TAILQ_INSERT_TAIL(&ctx->spare_fd_q, ev_fd, qent);
		}
		return NULL;
	}

	if (!flag.ev_fd_inq) {
		TAILQ_INIT(&ev_fd->noti_q);
		TAILQ_INSERT_TAIL(&ctx->fd_q, ev_fd, qent);
		ev_fd->fd = fd;
	}
	TAILQ_INSERT_TAIL(&ev_fd->noti_q, ev_noti, qent);
	ev_noti->fd = fd;
	ev_noti->cb = cb;
	ev_noti->cbarg = cbarg;
	ev_noti->ev_wait = ev_wait;
	ev_noti->due = due;
	return (void*)ev_noti;
}

void aloe_ev_cancel(void *_ctx, void *ev) {
	aloe_ev_ctx_t *ctx = (aloe_ev_ctx_t*)_ctx;
	aloe_ev_ctx_noti_t *ev_noti = (aloe_ev_ctx_noti_t*)ev;
	aloe_ev_ctx_fd_t *ev_fd;

	if ((ev_fd = fd_q_find(&ctx->fd_q, ev_noti->fd, 0))
	        && noti_q_find(&ev_fd->noti_q, ev_noti, 1)) {
		TAILQ_INSERT_TAIL(&ctx->spare_noti_q, ev_noti, qent);
		if (TAILQ_EMPTY(&ev_fd->noti_q)) {
			TAILQ_REMOVE(&ctx->fd_q, ev_fd, qent);
			TAILQ_INSERT_TAIL(&ctx->spare_fd_q, ev_fd, qent);
		}
		return;
	}

	if (noti_q_find(&ctx->noti_q, ev_noti, 1)) {
		TAILQ_INSERT_TAIL(&ctx->spare_noti_q, ev_noti, qent);
		return;
	}
}

int aloe_ev_once(void *_ctx) {
	aloe_ev_ctx_t *ctx = (aloe_ev_ctx_t*)_ctx;
	int r, fdmax = -1;
	fd_set rdset, wrset, exset;
	aloe_ev_ctx_noti_t *ev_noti, *ev_noti_safe;
	aloe_ev_ctx_fd_t *ev_fd, *ev_fd_safe;
	struct timeval sel_tmr = {.tv_sec = ALOE_EV_INFINITE};
	struct timespec ts, *due = NULL;

	FD_ZERO(&rdset); FD_ZERO(&wrset); FD_ZERO(&exset);

	TAILQ_FOREACH(ev_fd, &ctx->fd_q, qent) {
		if (ev_fd->fd != -1 && ev_fd->fd > fdmax) fdmax = ev_fd->fd;
		TAILQ_FOREACH(ev_noti, &ev_fd->noti_q, qent) {
			if (ev_fd->fd != -1) {
				if (ev_noti->ev_wait & aloe_ev_flag_read) {
					FD_SET(ev_fd->fd, &rdset);
				}
				if (ev_noti->ev_wait & aloe_ev_flag_write) {
					FD_SET(ev_fd->fd, &wrset);
				}
				if (ev_noti->ev_wait & aloe_ev_flag_except) {
					FD_SET(ev_fd->fd, &exset);
				}
			}
			if (ev_noti->due.tv_sec != ALOE_EV_INFINITE && (!due
					|| ALOE_TIMESEC_CMP(ev_noti->due.tv_sec, ev_noti->due.tv_nsec,
							due->tv_sec, due->tv_nsec) < 0)) {
				due = &ev_noti->due;
			}
		}
	}

	// convert due for select()
	if (due) {
		if ((clock_gettime(CLOCK_MONOTONIC, &ts)) != 0) {
			r = errno;
			log_e("Failed to get time: %s(%d)\n", strerror(r), r);
			return r;
		}
		if (ALOE_TIMESEC_CMP(ts.tv_sec, ts.tv_nsec,
				due->tv_sec, due->tv_nsec) < 0) {
			ALOE_TIMESEC_SUB(due->tv_sec, due->tv_nsec,
					ts.tv_sec, ts.tv_nsec, ts.tv_sec, ts.tv_nsec, 1000000000ul);
			sel_tmr.tv_sec = ts.tv_sec; sel_tmr.tv_usec = ts.tv_nsec / 1000ul;
		} else {
			sel_tmr.tv_sec = 0; sel_tmr.tv_usec = 0;
		}
	} else if (fdmax == -1) {
		// infinite waiting
		sel_tmr.tv_sec = 0; sel_tmr.tv_usec = 0;
	}

#if ALOE_EV_PREVENT_BUSY_WAITING
	if (sel_tmr.tv_sec == 0 && sel_tmr.tv_usec < ALOE_EV_PREVENT_BUSY_WAITING) {
		sel_tmr.tv_usec = ALOE_EV_PREVENT_BUSY_WAITING;
	}
#endif

	if ((fdmax = select(fdmax + 1, &rdset, &wrset, &exset,
			(sel_tmr.tv_sec == ALOE_EV_INFINITE ? NULL : &sel_tmr))) < 0) {
		r = errno;
//		if (r == EINTR) {
//			log_d("Interrupted when wait IO: %s(%d)\n", strerror(r), r);
//		} else {
			log_e("Failed to wait IO: %s(%d)\n", strerror(r), r);
//		}
		return r;
	}

	if ((fdmax = clock_gettime(CLOCK_MONOTONIC, &ts)) != 0) {
		r = errno;
		log_e("Failed to get time: %s(%d)\n", strerror(r), r);
		return r;
	}

	TAILQ_FOREACH_SAFE(ev_fd, &ctx->fd_q, qent, ev_fd_safe) {
		unsigned triggered = 0;

		if (fdmax > 0 && ev_fd->fd != -1) {
			if (FD_ISSET(ev_fd->fd, &rdset)) {
				triggered |= aloe_ev_flag_read;
				fdmax--;
			}
			if (FD_ISSET(ev_fd->fd, &wrset)) {
				triggered |= aloe_ev_flag_write;
				fdmax--;
			}
			if (FD_ISSET(ev_fd->fd, &exset)) {
				triggered |= aloe_ev_flag_except;
				fdmax--;
			}
		}
		TAILQ_FOREACH_SAFE(ev_noti, &ev_fd->noti_q, qent, ev_noti_safe) {
			if (!(ev_noti->ev_noti = triggered & ev_noti->ev_wait)
					&& ev_noti->due.tv_sec != ALOE_EV_INFINITE
					&& ALOE_TIMESEC_CMP(ev_noti->due.tv_sec, ev_noti->due.tv_nsec,
							ts.tv_sec, ts.tv_nsec) <= 0) {
				ev_noti->ev_noti |= aloe_ev_flag_time;
			}
			if (ev_noti->ev_noti) {
				TAILQ_REMOVE(&ev_fd->noti_q, ev_noti, qent);
				TAILQ_INSERT_TAIL(&ctx->noti_q, ev_noti, qent);
			}
		}
		if (TAILQ_EMPTY(&ev_fd->noti_q)) {
			TAILQ_REMOVE(&ctx->fd_q, ev_fd, qent);
			TAILQ_INSERT_TAIL(&ctx->spare_fd_q, ev_fd, qent);
		}
	}

	fdmax = 0;
	while ((ev_noti = TAILQ_FIRST(&ctx->noti_q))) {
		int fd = ev_noti->fd;
		aloe_ev_noti_cb_t cb = ev_noti->cb;
		void *cbarg = ev_noti->cbarg;
		unsigned triggered = ev_noti->ev_noti;

		fdmax++;
		TAILQ_REMOVE(&ctx->noti_q, ev_noti, qent);
		TAILQ_INSERT_TAIL(&ctx->noti_q, ev_noti, qent);
		(*cb)(fd, triggered, cbarg);
	}
	return fdmax;
}

void* aloe_ev_init(void) {
	aloe_ev_ctx_t *ctx;

	if (!(ctx = malloc(sizeof(*ctx)))) {
		log_e("malloc ev ctx\n");
		return NULL;
	}
	TAILQ_INIT(&ctx->fd_q);
	TAILQ_INIT(&ctx->spare_fd_q);
	TAILQ_INIT(&ctx->noti_q);
	TAILQ_INIT(&ctx->spare_noti_q);
	return (void*)ctx;
}

void aloe_ev_destroy(void *_ctx) {
	aloe_ev_ctx_t *ctx = (aloe_ev_ctx_t*)_ctx;
	aloe_ev_ctx_noti_t *ev_noti;
	aloe_ev_ctx_fd_t *ev_fd;

	while ((ev_fd = TAILQ_FIRST(&ctx->fd_q))) {
		TAILQ_REMOVE(&ctx->fd_q, ev_fd, qent);
		while ((ev_noti = TAILQ_FIRST(&ev_fd->noti_q))) {
			TAILQ_REMOVE(&ev_fd->noti_q, ev_noti, qent);
			free(ev_noti);
		}
		free(ev_fd);
	}
	while ((ev_fd = TAILQ_FIRST(&ctx->spare_fd_q))) {
		TAILQ_REMOVE(&ctx->fd_q, ev_fd, qent);
		free(ev_fd);
	}
	while ((ev_noti = TAILQ_FIRST(&ctx->noti_q))) {
		TAILQ_REMOVE(&ctx->noti_q, ev_noti, qent);
		free(ev_noti);
	}
	while ((ev_noti = TAILQ_FIRST(&ctx->spare_noti_q))) {
		TAILQ_REMOVE(&ctx->spare_noti_q, ev_noti, qent);
		free(ev_noti);
	}
	free(ctx);
}
