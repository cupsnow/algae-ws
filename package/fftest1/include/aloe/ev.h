/**
 * @author joelai
 */

#ifndef _H_ALOE_EV_MAIN
#define _H_ALOE_EV_MAIN

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

/** @mainpage
 *
 * # Introduction
 *
 * - Namespace is aloe_ev.
 * - Hack to check class size when build time. Referenced from <a href="https://stackoverflow.com/a/53884709">here</a>
 *   > ```
 *   > char checker(int);
 *   > char checkSizeOfInt[sizeof(usart->ctrla)] = {checker(&checkSizeOfInt)};
 *   > ```
 *   > ```
 *   > note: expected 'int' but argument is of type 'char (*)[4]'
 *   > ```
 */

/** @defgroup ALOE_EV_API Event driven API
 * @brief Event driven API.
 */

#ifdef __cplusplus
extern "C" {
#endif

/** @addtogroup ALOE_EV_API
 * @{
 */

/** Enumeration about event trigger. */
typedef enum aloe_ev_flag_enum {
	aloe_ev_flag_read = (1 << 0), /**< Readable. */
	aloe_ev_flag_write = (1 << 1), /**< Writable. */
	aloe_ev_flag_except = (1 << 2),/**< Exception. */
	aloe_ev_flag_time = (1 << 3), /**< Timeout. */
} aloe_ev_flag_t;

/** Indicate no timeout. */
#define ALOE_EV_INFINITE ((unsigned long)-1)

/** Callback for notify event to user. */
typedef void (*aloe_ev_noti_cb_t)(int fd, unsigned ev_noti, void *cbarg);

/** Put the event into internal process. */
void* aloe_ev_put(void *ctx, int fd, aloe_ev_noti_cb_t cb, void *cbarg,
		unsigned ev_wait, unsigned long sec, unsigned long usec);

/** Remove the event from internal process. */
void aloe_ev_cancel(void *ctx, void *ev);

/** Process a loop. */
int aloe_ev_once(void *ctx);

/** Initialize context. */
void* aloe_ev_init(void);

/** Free context. */
void aloe_ev_destroy(void *ctx);

/** @} ALOE_EV_API */

#ifdef __cplusplus
} // extern "C"
#endif

#endif /* _H_ALOE_EV_MAIN */
