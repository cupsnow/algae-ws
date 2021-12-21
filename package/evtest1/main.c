/**
 * @author joelai
 */

#include "priv.h"

#define log_m(_lvl, _fmt, _args...) printf(_lvl "%s #%d " _fmt, __func__, __LINE__, ##_args)
#define log_e(_args...) log_m("ERRORs ", ##_args)
#define log_d(_args...) log_m("Debug ", ##_args)

static aloe_ev_head_t evhead = {
#ifdef ALOE_EV_CONTAINER_RB
	.rbtree = RB_INITIALIZER(evhead.rbtree),
#endif
#ifdef ALOE_EV_CONTAINER_TAILQ
	.tailq = TAILQ_HEAD_INITIALIZER(evhead.tailq),
#endif
};

static aloe_ev_rbtree_t evtree = RB_INITIALIZER(&evtree);
static char ev_quit = 0;
static aloe_ev_t ev_ctl;

static const char *opt_ctl = "aloe_evb_ctrl";
static struct {
	const char *str;
	int str_len;
	char resp;
} opt_cmd = {0};
static const char opt_short[] = "-:hc:";
static struct option opt_long[] = {
	{"help", no_argument, NULL, 'h'},
	{"cmd", required_argument, NULL, 'c'},
	{"ctrl", required_argument, NULL, 't'},
	{0},
};

typedef struct conn_rec {
	aloe_ev_t ev;

} conn_t;

static void main_sigact(int sig, siginfo_t *info, void *ucontext) {
	if (sig == SIGINT) {
		log_d("SIGINT\n");
		return;
	}
	if (sig == SIGQUIT) {
		log_d("SIGQUIT\n");
		return;
	}
	if (sig == SIGKILL) {
		log_d("SIGKILL\n");
		return;
	}
}

static void cmd_server_xfer(struct aloe_ev_rec *ev, unsigned triggered) {
	conn_t *conn = aloe_container_of(ev, conn_t, ev);
	int r, len;
	char buf[200];

	if (triggered & aloe_ev_flag_read) {
		if ((len = read(ev->fd, buf, sizeof(buf) - 1)) < 0) {
			r = errno;
			if (!ALOE_ENO_NONBLOCKING(r)) {
				log_e("Failed client received: %s(%d)\n", strerror(r), r);
				goto finally;
			}
			r = 0;
			goto finally;
		}
		if (len == 0) {
			r = EPIPE;
			log_d("Closed connection\n");
			goto finally;
		}
		buf[len] = '\0';
		log_d("Server recv: %s\n", buf);
	}
	r = 0;
finally:
	if (r == 0 && opt_cmd.str_len > 0) {
		aloe_ev_timeout(ev, 1, 0);
		aloe_ev_put(&evtree, ev);
		return;
	}
	close(ev->fd);
	ev->fd = -1;
	ev_quit = 1;
}

static void cmd_server_accept(struct aloe_ev_rec *ev, unsigned triggered) {
	int r, fd_conn = -1;
	conn_t *conn;

	if (triggered & aloe_ev_flag_read) {
		if ((fd_conn = accept(ev_ctl.fd, NULL, NULL)) == -1) {
			r = errno;
			if (!ALOE_ENO_NONBLOCKING(r)) {
				log_e("Failed accept control socket: %s(%d)\n", strerror(r), r);
				goto finally;
			}
			r = 0;
			goto finally;
		}

		if ((conn = malloc(sizeof(*conn))) == NULL) {
			close(fd_conn);

			r = ENOMEM;
			log_e("Failed alloc memory for connection\n");
			goto finally;
		}
		conn->ev.fd = fd_conn;
		conn->ev.cb = &cmd_server_xfer;
		conn->ev.wanted = aloe_ev_flag_read;
		aloe_ev_timeout(&conn->ev, 1, 0);
		aloe_ev_put(&evtree, &conn->ev);
	}
	r = 0;
finally:
	if (r == 0) {
		aloe_ev_put(&evtree, ev);
		return;
	}
	close(ev->fd);
	ev->fd = -1;
	ev_quit = 1;
}

static void cmd_client_xfer(struct aloe_ev_rec *ev, unsigned triggered) {
	int r;
	char buf[200];

	if (triggered & aloe_ev_flag_read) {
		if ((r = read(ev->fd, buf, sizeof(buf) - 1)) < 0) {
			r = errno;
			if (!ALOE_ENO_NONBLOCKING(r)) {
				log_e("Failed client received: %s(%d)\n", strerror(r), r);
				goto finally;
			}
			r = 0;
			goto finally;
		}
		if (r == 0) {
			r = EPIPE;
			log_d("Remote closed connection\n");
			goto finally;
		}
		buf[r] = '\0';
		log_d("Client recv resp: %s\n", buf);
	}
	if ((triggered & aloe_ev_flag_write) && (opt_cmd.str_len > 0)) {
		if ((r = write(ev->fd, opt_cmd.str, opt_cmd.str_len)) < 0) {
			r = errno;
			if (!ALOE_ENO_NONBLOCKING(r)) {
				log_e("Failed client send command: %s(%d)\n", strerror(r), r);
				goto finally;
			}
			r = 0;
			goto finally;
		}
		if ((opt_cmd.str_len -= r) > 0) {
			opt_cmd.str += r;
		} else {
			log_d("Client sent command done\n");
		}
	}
	if (triggered & aloe_ev_flag_time) {
		r = ETIMEDOUT;
		goto finally;
	}
	r = 0;
finally:
	if (r == 0 && opt_cmd.str_len > 0) {
		aloe_ev_timeout(ev, 1, 0);
		aloe_ev_put(&evtree, ev);
		return;
	}
	close(ev->fd);
	ev->fd = -1;
	ev_quit = 1;
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
	int opt_op, opt_idx, r;
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
			opt_cmd.str_len = strlen(opt_cmd.str = optarg);
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
	if ((ev_ctl.fd = socket(AF_UNIX, SOCK_DGRAM, 0)) == -1) {
		r = errno;
		log_e("Failed open control socket: %s(%d)\n", strerror(r), r);
		goto finally;
	}
	if ((r = aloe_file_nonblock(ev_ctl.fd, 1)) != 0) {
		log_e("Failed set nonblocking control socket\n");
		goto finally;
	}
	if (opt_cmd.str_len > 0) {
		if ((r = connect(ev_ctl.fd, (struct sockaddr*)&ctrl_sa, ctrl_sa_len)) != 0) {
			r = errno;
			if (!ALOE_ENO_NONBLOCKING(r)) {
				log_e("Failed connect to control socket: %s(%d)\n", strerror(r), r);
				goto finally;
			}
		}

		// schedule event to write whether NONBLOCKING or successful connection establish
		ev_ctl.cb = &cmd_client_xfer;
		ev_ctl.wanted = aloe_ev_flag_write | aloe_ev_flag_read;
		aloe_ev_timeout(&ev_ctl, 1, 0);
	} else {
		if ((r = bind(ev_ctl.fd, (struct sockaddr*)&ctrl_sa, ctrl_sa_len)) != 0 ||
				(r = listen(ev_ctl.fd, 1)) != 0) {
			r = errno;
			log_e("Failed listen control socket: %s(%d)\n", strerror(r), r);
			goto finally;
		}

//		if ((r = accept(ev_ctl.fd, NULL, NULL)) != 0) {
//			r = errno;
//			if (!ALOE_ENO_NONBLOCKING(r)) {
//				log_e("Failed accept control socket: %s(%d)\n", strerror(r), r);
//				goto finally;
//			}
//		} else {
//			conn_t *conn;
//
//			if ((conn = malloc(sizeof(*conn))) == NULL) {
//				r = ENOMEM;
//				log_e("Failed alloc memory for connection\n");
//				goto finally;
//			}
//			conn->ev.fd = r;
//			conn->ev.cb = &cmd_server_recv;
//			ev_ctl.wanted = aloe_ev_flag_read;
//			aloe_ev_timeout(&conn->ev, 5, 0);
//			aloe_ev_put(&evtree, &conn->ev);
//		}
		// schedule event to read for more connection accept
		ev_ctl.cb = &cmd_server_accept;
		ev_ctl.wanted = aloe_ev_flag_read;
		aloe_ev_timeout(&ev_ctl, ALOE_EV_INFINITE, ALOE_EV_INFINITE);
	}
	aloe_ev_put(&evtree, &ev_ctl);

	sigact.sa_sigaction = &main_sigact;
    sigemptyset(&sigact.sa_mask);
    sigact.sa_flags = SA_SIGINFO;

#define sig_reg(_s) \
    if ((r = sigaction((_s), &sigact, NULL)) != 0) { \
    	r = errno; \
    	log_e("Failed hook " aloe_stringify(_s) ": %s(%d)\n", strerror(r), r); \
    	goto finally; \
    }
    sig_reg(SIGINT);
    sig_reg(SIGKILL);
    sig_reg(SIGQUIT);

    while (!ev_quit) aloe_ev_once(&evtree);
	r = 0;
finally:
	return r;
}
