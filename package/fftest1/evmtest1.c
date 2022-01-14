/**
 * @author joelai
 */

#include "priv.h"

//#define log_m(_lvl, _fmt, _args...) printf(_lvl "%s #%d " _fmt, __func__, __LINE__, ##_args)
#define log_m(_lvl, _fmt, _args...) _log_m(_lvl, __func__, __LINE__, _fmt, ##_args)
#define log_e(_args...) log_m("ERRORs ", ##_args)
#define log_d(_args...) log_m("Debug ", ##_args)

#define CTRL_PATH "$evmtest1.ctrl"

static struct {
	unsigned quit: 1;

} impl = {0};
void *ev_ctx = NULL, *cfg_ctx = NULL;

int _log_v(const char *lvl, const char *func_name, int lno, const char *fmt,
		va_list va) {
	char buf[300];
	aloe_fb_t fb = {.data = buf, .cap = sizeof(buf), .lmt = 0, .pos = 0};
	int r;
	struct timespec ts;
	struct tm tm;

	clock_gettime(CLOCK_REALTIME, &ts);
	localtime_r(&ts.tv_sec, &tm);
	if ((r = snprintf((char*)fb.data + fb.lmt, fb.cap - fb.lmt,
	        "%02d:%02d:%02d:%06d ", tm.tm_hour, tm.tm_min, tm.tm_sec,
	        (int)(ts.tv_nsec / 1000))) <= 0 || (fb.lmt += r) >= fb.cap) {
		goto finally;
	}
	if ((r = snprintf((char*)fb.data + fb.lmt, fb.cap - fb.lmt,
			"%s %s #%d ", lvl, func_name, lno)) <= 0 || (fb.lmt += r) >= fb.cap) {
		goto finally;
	}
	if (fmt) {
		if ((r = vsnprintf((char*)fb.data + fb.lmt, fb.cap - fb.lmt, fmt, va))
		        <= 0 || (fb.lmt += r) >= fb.cap) {
			goto finally;
		}
	}
finally:
	if (fb.lmt >= fb.cap) {
		static const char abbr[] = "...\n";
		int abbr_sz = strlen(abbr);

		if (fb.cap > abbr_sz) {
			// also copy abbr trailing-zero
			memcpy((char*)fb.data + fb.cap - 1 - abbr_sz, abbr, abbr_sz + 1);
			// return size excluding trailing-zero
			fb.lmt = fb.cap - 1;
		}
	}
	if (fb.lmt > 0) fwrite(fb.data, fb.lmt, 1, stdout);
	return fb.lmt;
}

int _log_m(const char *lvl, const char *func_name, int lno,
		const char *fmt, ...) {
	int r;
	va_list va;
	va_start(va, fmt);
	r = _log_v(lvl, func_name, lno, fmt, va);
	va_end(va);
	return r;
}

static const char opt_short[] = "-:ht:";
static struct option opt_long[] = {
	{"help", no_argument, NULL, 'h'},
	{"ctrl", required_argument, NULL, 't'},
	{0},
};

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
		"    -t, --ctrl=<CTRL>  Control socket path (\"%s\")\n"
		"\n",
		((argc > 0) && argv && argv[0] ? argv[0] : "Program"),
		CTRL_PATH);
}

int main(int argc, char **argv) {
	int opt_op, opt_idx, r, i;
	typedef struct mod_rec {
		const aloe_mod_t *op;
		TAILQ_ENTRY(mod_rec) qent;
		void *ctx;
	} mod_t;
	TAILQ_HEAD(mod_queue_rec, mod_rec) mod_q = TAILQ_HEAD_INITIALIZER(mod_q);
	mod_t *mod;

	optind = 0;
	while ((opt_op = getopt_long(argc, argv, opt_short, opt_long,
			&opt_idx)) != -1) {
		if (opt_op == 'h') {
			help(argc, argv);
			r = 1;
			goto finally;
		}
		if (opt_op == 't') {
//			appcfg.ctrl_path = optarg;
			continue;
		}
	}

	if (!(cfg_ctx = aloe_cfg_init())) {
		r = ENOMEM;
		log_e("aloe_cfg_init\n");
		goto finally;
	}

	if (!(ev_ctx = aloe_ev_init())) {
		r = ENOMEM;
		log_e("aloe_ev_init\n");
		goto finally;
	}

#define MOD_INIT(_op) { \
		extern const aloe_mod_t _op; \
		static mod_t mod = {&_op}; \
		if (!(mod.ctx = (*mod.op->init)())) { \
			log_e("init mod: %s\n", mod.op->name); \
			goto finally; \
		} \
		TAILQ_INSERT_TAIL(&mod_q, &mod, qent); \
	}
	MOD_INIT(mod_cli);

    while (!impl.quit) {
    	aloe_ev_once(ev_ctx);
    	log_d("enter\n");
    }
	r = 0;
finally:
	while ((mod = TAILQ_LAST(&mod_q, mod_queue_rec))) {
		TAILQ_REMOVE(&mod_q, mod, qent);
		mod->op->destroy(mod->ctx);
	}
	if (ev_ctx) {
		aloe_ev_destroy(ev_ctx);
	}
	if (cfg_ctx) {
		aloe_cfg_destroy(cfg_ctx);
	}
	return r;
}
