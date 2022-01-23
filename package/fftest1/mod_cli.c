/* 
 * @author joelai
 */
#include "priv.h"

#define log_m(_lvl, _fmt, _args...) _log_m(_lvl, __func__, __LINE__, _fmt, ##_args)
#define log_e(_args...) log_m("ERROR ", ##_args)
#define log_d(_args...) log_m("Debug ", ##_args)

extern int _log_m(const char *lvl, const char *func_name, int lno,
		const char *fmt, ...);
extern void *ev_ctx;

static int instanceId = 0;
static char mod_name[] = "cli";

typedef struct {
	int instanceId, fd_ctrl;

} ctx_t;

static void* init(void) {
	ctx_t *ctx;

	if ((ctx = malloc(sizeof(*ctx))) == NULL) {
		log_e("alloc instance\n");
		return NULL;
	}
	ctx->instanceId = instanceId++;
	log_d("%s[%d]\n", mod_name, ctx->instanceId);

	return (void*)ctx;
}

static void destroy(void *_ctx) {
	ctx_t *ctx = (ctx_t*)_ctx;

	log_d("%s[%d]\n", mod_name, ctx->instanceId);
	free(ctx);
}

static int ioctl(void *_ctx, void *args) {
	ctx_t *ctx = (ctx_t*)_ctx;

	log_d("%s[%d]\n", mod_name, ctx->instanceId);
	return 0;
}

const aloe_mod_t mod_cli = {.name = mod_name, .init = &init, .destroy = &destroy,
        .ioctl = &ioctl};
