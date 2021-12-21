/**
 * @author joelai
 */

#include "priv.h"

#define log_m(_lvl, _fmt, _args...) printf(_lvl "%s #%d " _fmt, __func__, __LINE__, ##_args)
#define log_e(_args...) log_m("ERRORs ", ##_args)
#define log_d(_args...) log_m("Debug ", ##_args)

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
	if (sa_len) *sa_len = offsetof(struct sockaddr_un, sun_path) + path_size + 1;
	return 0;
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

int aloe_ev_timeout(aloe_ev_t *ev, unsigned long sec, unsigned long nsec) {
	struct timespec ts;
	int r;

	if (sec == ALOE_EV_INFINITE || nsec == ALOE_EV_INFINITE) {
		ev->timeline.tv_sec = ALOE_EV_INFINITE;
		ev->timeline.tv_nsec = 0;
		return 0;
	}
	if ((r = clock_gettime(CLOCK_MONOTONIC, &ts)) != 0) {
		r = errno;
		log_e("Failed to get time: %s(%d)\n", strerror(r), r);
		/* forced timeout */
		ev->timeline.tv_sec = 0;
		ev->timeline.tv_nsec = 0;
		return r;
	}
	ALOE_TIMESEC_ADD(ts.tv_sec, ts.tv_nsec, sec, nsec, ev->timeline.tv_sec,
			ev->timeline.tv_nsec, 1000000000ul);
	return 0;
}

static aloe_ev_fd_t* ev_fd_get(aloe_ev_fd_queue_t *q, int fd) {
	aloe_ev_fd_t *ev_fd;

	TAILQ_FOREACH(ev_fd, q, qent) {
		if (ev_fd->fd == fd) return ev_fd;
	}
	return NULL;
}

void* aloe_ev_put(void *_ctx, int fd,
		void (*cb)(int fd, unsigned ev_noti, void *cbarg), void *cbarg,
		unsigned ev_wait, unsigned long sec, unsigned long usec) {
	aloe_ev_ctx_t *ctx = (aloe_ev_ctx_t*)_ctx;
	aloe_ev_fd_t *ev_fd;
	aloe_ev_noti_t *ev_noti;


}

void aloe_ev_cancel(void *ctx, void *ev) {

}

int aloe_ev_once(aloe_ev_head_t *ev_head) {
#define ALOE_EV_MIN_TIMELINE 5 /* ms */
	int r, fdmax;
	fd_set rdset, wrset, exset;
	aloe_ev_t *ev, *ev_safe;
	struct timespec ts;
	const struct timespec *timeline;
	struct timeval tv = {.tv_sec = ALOE_EV_INFINITE};

	if (
#if defined(ALOE_EV_CONTAINER_TAILQ)
			TAILQ_EMPTY(&ev_head->tailq)
#elif defined(ALOE_EV_CONTAINER_RB)
			RB_EMPTY(&ev_head->rbtree)
#endif
			) {
		log_e("Failed to run empty ev head\n");
		return EINVAL;
	}

	// find timeline, fdset (for select())
	FD_ZERO(&rdset); FD_ZERO(&wrset); FD_ZERO(&exset);
	fdmax = -1;
	timeline = NULL;
#if defined(ALOE_EV_CONTAINER_TAILQ)
	TAILQ_FOREACH(ev, &ev_head->tailq, qent)
#elif defined(ALOE_EV_CONTAINER_RB)
	RB_FOREACH(ev, aloe_ev_rbtree_rec, &ev_head->rbtree)
#endif
	{
		if (ev->fd != -1) {
			if (ev->fd > fdmax) fdmax = ev->fd;
			if (ev->wanted & aloe_ev_flag_read) FD_SET(ev->fd, &rdset);
			if (ev->wanted & aloe_ev_flag_write) FD_SET(ev->fd, &wrset);
			if (ev->wanted & aloe_ev_flag_except) FD_SET(ev->fd, &exset);
		}
		if (ev->timeline.tv_sec != ALOE_EV_INFINITE && (!timeline ||
				ALOE_TIMESEC_CMP(ev->timeline.tv_sec, ev->timeline.tv_nsec,
						timeline->tv_sec, timeline->tv_nsec) < 0)) {
			timeline = &ev->timeline;
		}
	}

	// convert timeline to timeval (for select())
	if (timeline) {
		if ((r = clock_gettime(CLOCK_MONOTONIC, &ts)) != 0) {
			r = errno;
			log_e("Failed to get time: %s(%d)\n", strerror(r), r);
			return r;
		}
		if (ALOE_TIMESEC_CMP(ts.tv_sec, ts.tv_nsec, timeline->tv_sec,
				timeline->tv_nsec) < 0) {
			ALOE_TIMESEC_SUB(timeline->tv_sec, timeline->tv_nsec, ts.tv_sec,
					ts.tv_nsec, ts.tv_sec, ts.tv_nsec, 1000000000ul);
			tv.tv_sec = ts.tv_sec; tv.tv_usec = ts.tv_nsec / 1000ul;
		} else {
			tv.tv_sec = 0; tv.tv_usec = 0;
		}
	}

	// prevent busy waiting;
	if (tv.tv_sec == 0 && tv.tv_usec < ALOE_EV_MIN_TIMELINE * 1000ul) {
		tv.tv_usec = ALOE_EV_MIN_TIMELINE * 1000ul;
	}

	if ((r = select(fdmax, &rdset, &wrset, &exset,
			(tv.tv_sec == ALOE_EV_INFINITE ? NULL : &tv))) < 0) {
		r = errno;
		if (r == EINTR) {
			log_d("Interrupted when wait IO: %s(%d)\n", strerror(r), r);
		} else {
			log_e("Failed to wait IO: %s(%d)\n", strerror(r), r);
		}
		return r;
	}

	// count for io triggered
	fdmax = r;

	if ((r = clock_gettime(CLOCK_MONOTONIC, &ts)) != 0) {
		r = errno;
		log_e("Failed to get time: %s(%d)\n", strerror(r), r);
		return r;
	}

#if defined(ALOE_EV_CONTAINER_TAILQ)
	TAILQ_FOREACH_SAFE(ev, &ev_head->tailq, qent, ev_safe)
#else
	RB_FOREACH_SAFE(ev, aloe_ev_rbtree_rec, &ev_head->rbtree, ev_safe)
#endif
	{
		ev->triggered = 0;
		if (fdmax > 0 && ev->fd != -1) {
			if (FD_ISSET(ev->fd, &rdset)) {
				ev->triggered |= aloe_ev_flag_read;
				fdmax--;
			}
			if (FD_ISSET(ev->fd, &wrset)) {
				ev->triggered |= aloe_ev_flag_write;
				fdmax--;
			}
			if (FD_ISSET(ev->fd, &exset)) {
				ev->triggered |= aloe_ev_flag_except;
				fdmax--;
			}
		}

		// timeout when IO not triggered
		if (!ev->triggered && ev->timeline.tv_sec != ALOE_EV_INFINITE &&
				ALOE_TIMESEC_CMP(ev->timeline.tv_sec, ev->timeline.tv_nsec,
						ts.tv_sec, ts.tv_nsec) <= 0) {
			ev->triggered |= aloe_ev_flag_time;
		}

		// pop when triggered
		if (ev->triggered) {
			aloe_ev_pop(evtree, ev);
			ev->cb(ev, ev->triggered);
		}
	}
	return 0;
}

