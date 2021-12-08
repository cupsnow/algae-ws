/**
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <time.h>
#include <sys/time.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <netinet/ip.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <signal.h>
#include <getopt.h>
#include <pthread.h>

#include <aloe/compat/openbsd/sys/tree.h>
#include <aloe/compat/openbsd/sys/queue.h>

#define log_m(_lvl, _fmt, _args...) printf(_lvl "%s #%d " _fmt, __func__, __LINE__, ##_args)
#define log_e(_args...) log_m("ERRORs ", ##_args)
#define log_d(_args...) log_m("Debug ", ##_args)

typedef struct {
	void *addr;
	size_t len, pa;
} aloe_mmaddr_t;
#define aloe_mmaddr_INITIALIZER {.addr = MAP_FAILED}

static void aloe_file_munmap(aloe_mmaddr_t *mmaddr) {
	if (mmaddr && mmaddr->addr != MAP_FAILED) {
		munmap((void*)((unsigned long)mmaddr->addr - mmaddr->pa),
				mmaddr->len + mmaddr->pa);
	}
}

static int aloe_file_mmap(aloe_mmaddr_t *mmaddr, int fd, size_t offset, size_t len) {
	int r;
	struct stat fst;
	aloe_mmaddr_t _mmaddr = {.addr = MAP_FAILED};

	if (fstat(fd, &fst) == -1) {
		r = errno;
		jl_e("Get file stat: %s(%d)\n", strerror(r), r);
		return r;
	}
	if (offset >= fst.st_size) {
		r = ERANGE;
		jl_e("Offset %u but size is %u\n", (unsigned)offset, (unsigned)fst.st_size);
		return r;
	}
	if (len == (size_t)-1) {
		_mmaddr.len = fst.st_size;
	} else if (len > 0 && len + offset > fst.st_size) {
		_mmaddr.len = fst.st_size - offset;
	} else {
		_mmaddr.len = len;
	}
	_mmaddr.pa = offset & (sysconf(_SC_PAGE_SIZE) - 1);
	if ((_mmaddr.addr = mmap(NULL, _mmaddr.len + _mmaddr.pa, PROT_READ, MAP_PRIVATE, fd,
			offset - _mmaddr.pa)) == MAP_FAILED) {
		r = errno;
		jl_e("Memory mapped file: %s(%d)\n", strerror(r), r);
		return r;
	}
	_mmaddr.addr = (void*)((unsigned long)_mmaddr.addr + _mmaddr.pa);
	memcpy(mmaddr, &_mmaddr, sizeof(_mmaddr));
	return 0;
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

#define ALOE_ENO_NONBLOCKING(_e) ((_e) == EAGAIN || (_e) == EINPROGRESS)

#define ALOE_TIMESEC_NORM(_sec, _subsec, _subscale) if ((_subsec) >= _subscale) { \
		(_sec) += (_subsec) / _subscale; \
		(_subsec) %= (_subscale); \
	}
/** Normalize timeval.
 *
 * |a|
 *
 * @param a
 * @return (a)
 */
struct timeval* aloe_timeval_norm(struct timeval *a) {
	if (a) ALOE_TIMESEC_NORM(a->tv_sec, a->tv_usec, 1000000ul);
	return a;
}

#define ALOE_TIMESEC_CMP(_a_sec, _a_subsec, _b_sec, _b_subsec) ( \
	((_a_sec) > (_b_sec)) ? 1 : \
	((_a_sec) < (_b_sec)) ? -1 : \
	((_a_subsec) > (_b_subsec)) ? 1 : \
	((_a_subsec) < (_b_subsec)) ? -1 : \
	0)
/** Compare 2 time in timeval.
 *
 * |a - b|
 *
 * @param a A normalized timeval
 * @param b A normalized timeval
 * @return 1, -1 or 0 if (a) later/early/equal then/to (b)
 */
int aloe_timeval_cmp(const struct timeval *a, const struct timeval *b) {
	return ALOE_TIMESEC_CMP(a->tv_sec, a->tv_usec, b->tv_sec, b->tv_usec);
}

#define ALOE_TIMESEC_SUB(_a_sec, _a_subsec, _b_sec, _b_subsec, _c_sec, \
		_c_subsec, _subscale) \
	if ((_a_subsec) < (_b_subsec)) { \
		(_c_sec) = (_a_sec) - (_b_sec) - 1; \
		(_c_subsec) = (_subscale) + (_a_subsec) - (_b_subsec); \
	} else { \
		(_c_sec) = (_a_sec) - (_b_sec); \
		(_c_subsec) = (_a_subsec) - (_b_subsec); \
	}
/** Subtraction 2 time in timeval.
 *
 * c = a - b
 *
 * @param a A normalized timeval, must later then (b)
 * @param b A normalized timeval, must early then (a)
 * @param c Hold result if not NULL
 * @return (c)
 */
struct timeval* aloe_timeval_sub(const struct timeval *a, const struct timeval *b,
		struct timeval *c) {
	ALOE_TIMESEC_SUB(a->tv_sec, a->tv_usec, b->tv_sec, b->tv_usec,
			c->tv_sec, c->tv_usec, 1000000ul);
	return c;
}

#define ALOE_TIMESEC_ADD(_a_sec, _a_subsec, _b_sec, _b_subsec, _c_sec, \
		_c_subsec, _subscale) do { \
	(_c_sec) = (_a_sec) + (_b_sec); \
	(_c_subsec) = (_a_subsec) + (_b_subsec); \
	ALOE_TIMESEC_NORM(_c_sec, _c_subsec, _subscale); \
} while(0)
struct timeval* aloe_timeval_add(const struct timeval *a, const struct timeval *b,
		struct timeval *c) {
	ALOE_TIMESEC_ADD(a->tv_sec, a->tv_usec, b->tv_sec, b->tv_usec,
			c->tv_sec, c->tv_usec, 1000000ul);
	return c;
}

typedef enum aloe_ev_flag_enum {
	aloe_ev_flag_read = (1 << 0),
	aloe_ev_flag_write = (1 << 1),
	aloe_ev_flag_except = (1 << 2),
	aloe_ev_flag_time = (1 << 3),
} aloe_ev_flag_t;

typedef struct aloe_ev_rec {
	void (*cb)(struct aloe_ev_rec*, unsigned triggered);
	int fd;
	unsigned wanted;

	/* Following used by internal management */
	struct timespec timeline;
	unsigned triggered;
	RB_ENTRY(aloe_ev_rec) rbent;
} aloe_ev_t;
typedef RB_HEAD(aloe_ev_rbtree_rec, aloe_ev_rec) aloe_ev_rbtree_t;
RB_PROTOTYPE(aloe_ev_rbtree_rec, aloe_ev_rec, rbent, );

static int aloe_ev_rbtree_cmp(aloe_ev_t *a, aloe_ev_t *b) {
	return a - b;
}
RB_GENERATE(aloe_ev_rbtree_rec, aloe_ev_rec, rbent, aloe_ev_rbtree_cmp);

#define ALOE_EV_INFINITE ((unsigned long)-1)

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

int aloe_ev_put(aloe_ev_rbtree_t *evtree, aloe_ev_t *ev) {
	RB_INSERT(aloe_ev_rbtree_rec, evtree, ev);
}

int aloe_ev_pop(aloe_ev_rbtree_t *evtree, aloe_ev_t *ev) {
	RB_REMOVE(aloe_ev_rbtree_rec, evtree, ev);
}

int aloe_ev_once(aloe_ev_rbtree_t *evtree) {
#define ALOE_EV_MIN_TIMELINE 5 /* ms */
	int r, fdmax;
	fd_set rdset, wrset, exset;
	aloe_ev_t *ev, *ev_rb;
	struct timespec ts;
	const struct timespec *timeline;
	struct timeval tv = {.tv_sec = ALOE_EV_INFINITE};

	if (RB_EMPTY(evtree)) {
		log_e("Failed to run empty evtree\n");
		return EINVAL;
	}

	// find timeline, fdset (for select())
	FD_ZERO(&rdset); FD_ZERO(&wrset); FD_ZERO(&exset);
	fdmax = -1;
	timeline = NULL;
	RB_FOREACH(ev, aloe_ev_rbtree_rec, evtree) {
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

	RB_FOREACH_SAFE(ev, aloe_ev_rbtree_rec, evtree, ev_rb) {
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

static aloe_ev_rbtree_t evtree = RB_INITIALIZER(&evtree);
static aloe_ev_t ev_ctl;
static const char *opt_ctl = "aloe_evb_ctrl";
static const char *opt_cmd = NULL;
static const char opt_short[] = "-:hc:";
static struct option opt_long[] = {
	{"help", no_argument, NULL, 'h'},
	{"cmd", required_argument, NULL, 'c'},
	{"ctrl", required_argument, NULL, 't'},
	{0},
};

static void main_sigact(int sig, siginfo_t *info, void *ucontext) {
	if (sig == SIGINT) {
		log_d("SIGINT\n");
		return;
	}
	if (sig == SIGQUIT) {
		log_d("SIGINT\n");
		return;
	}
	if (sig == SIGKILL) {
		log_d("SIGKILL\n");
		return;
	}
}

static void cmd_conn_accept(struct aloe_ev_rec *ev, unsigned triggered) {
	log_d("enter\n");
}

static void cmd_conn_send(struct aloe_ev_rec *ev, unsigned triggered) {
	log_d("enter\n");
}

static void help(int argc, char **argv) {
	int i;

#if 1
	for (i = 0; i < argc; i++) {
		log_d("argv[%d/%d]: %s\n", i + 1, argc, argv[i]);
	}
#endif

	printf(
		"COMMAND\n"
		"    %s [OPTIONS]\n"
		"\n"
		"OPTIONS\n"
		"    -h, --help         Show help\n"
		"    -c, --cmd=<CMD>    Command to send\n"
		"    -t, --ctrl=<CTRL>  Control socket path\n"
		"\n",
		(argc > 0) && argv && argv[0] ? argv[0] : "Program");
}

int main(int argc, char **argv) {
	int opt_op, opt_idx, r, ctrl_fd;
    struct sigaction sigact;
	struct sockaddr_un ctrl_sa;
	socklen_t ctrl_sa_len;

	optind = 0;
	while ((opt_op = getopt_long(argc, argv, opt_short, opt_long,
			&opt_idx)) != -1) {
		if (opt_op == 'h') {
			help(argc, argv);
			r = 1;
			goto finally;
		}
		if (opt_op == 't') {
			opt_ctl = optarg;
			continue;
		}
		if (opt_op == 'c') {
			opt_cmd = optarg;
			continue;
		}
	}

	if (!opt_ctl) {
		r = EINVAL;
		log_e("Miss control socket path\n");
		goto finally;
	}
	if ((r = aloe_local_socket_address(&ctrl_sa, &ctrl_sa_len, opt_ctl)) != 0) {
		log_e("Failed setup control socket address\n");
		goto finally;
	}
	if ((ctrl_fd = socket(AF_UNIX, SOCK_DGRAM, 0)) == -1) {
		r = errno;
		log_e("Failed open control socket: %s(%d)\n", strerror(r), r);
		goto finally;
	}
	if ((r = aloe_file_nonblock(ctrl_fd, 1)) != 0) {
		log_e("Failed set nonblocking control socket\n");
		goto finally;
	}
	if (opt_cmd) {
		if ((r = connect(ctrl_fd, (struct sockaddr*)&ctrl_sa, ctrl_sa_len)) != 0) {
			r = errno;
			if (!ALOE_ENO_NONBLOCKING(r)) {
				log_e("Failed connect to control socket: %s(%d)\n", strerror(r), r);
				goto finally;
			}
		}
		ev_ctl.cb = &cmd_conn_send;
		ev_ctl.fd = ctrl_fd;
		ev_ctl.wanted = aloe_ev_flag_write;
		aloe_ev_timeout(&ev_ctl, 1, 0);
	} else {
		if ((r = bind(ctrl_fd, (struct sockaddr*)&ctrl_sa, ctrl_sa_len)) != 0 ||
				(r = listen(ctrl_fd, 1)) != 0 ||
				(r = accept(ctrl_fd, NULL, NULL)) != 0) {
			r = errno;
			if (!ALOE_ENO_NONBLOCKING(r)) {
				log_e("Failed listen to control socket: %s(%d)\n", strerror(r), r);
				goto finally;
			}
		}
		ev_ctl.cb = &cmd_conn_accept;
		ev_ctl.fd = ctrl_fd;
		ev_ctl.wanted = aloe_ev_flag_read;
		aloe_ev_timeout(&ev_ctl, ALOE_EV_INFINITE, ALOE_EV_INFINITE);
	}
	aloe_ev_put(&evtree, &ev_ctl);

	sigact.sa_sigaction = &main_sigact;
    sigemptyset(&sigact.sa_mask);
    sigact.sa_flags = SA_SIGINFO;
    if ((r = sigaction(SIGINT, &sigact, NULL)) != 0) {
    	r = errno;
    	log_e("Failed hook SIGINT: %s(%d)\n", strerror(r), r);
    	goto finally;

    }
    if ((r = sigaction(SIGQUIT, &sigact, NULL)) != 0) {
    	r = errno;
    	log_e("Failed hook SIGQUIT: %s(%d)\n", strerror(r), r);
    	goto finally;

    }



	r = 0;
finally:
	return r;
}
