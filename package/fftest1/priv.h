/**
 * @author joelai
 */

#ifndef _H_ALOE_EV_PRIV
#define _H_ALOE_EV_PRIV

#ifdef HAVE_CONFIG_H
#  include <config.h>
#endif

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <stddef.h>

#include <aloe/ev.h>

#include <compat/openbsd/sys/tree.h>
#include <compat/openbsd/sys/queue.h>

/** @defgroup ALOE_EV_INTERNAL Internal
 * @brief Internal utility.
 *
 * @defgroup ALOE_EV_MISC Miscellaneous
 * @ingroup ALOE_EV_INTERNAL
 * @brief Trivial operation.
 *
 * @defgroup ALOE_EV_TIME Time
 * @ingroup ALOE_EV_INTERNAL
 * @brief Time variable.
 *
 * @defgroup ALOE_EV_IO IO
 * @ingroup ALOE_EV_INTERNAL
 * @brief IO for socket or file.
 *
 * @defgroup ALOE_EV_CFG
 * @ingroup ALOE_EV_INTERNAL
 * @brief Shared variable
 *
 */

#ifdef __cplusplus
extern "C" {
#endif

/** @addtogroup ALOE_EV_MISC
 * @{
 */

#define aloe_trex "🦖" /**< Trex. */
#define aloe_sauropod "🦕" /**< Sauropod. */
#define aloe_lizard "🦎" /**< Lizard. */

#define aloe_min(_a, _b) ((_a) <= (_b) ? (_a) : (_b))
#define aloe_max(_a, _b) ((_a) >= (_b) ? (_a) : (_b))
#define aloe_arraysize(_arr) (sizeof(_arr) / sizeof((_arr)[0]))

/** Stringify. */
#define _aloe_stringify(_s) # _s

/** Stringify support macro expansion. */
#define aloe_stringify(_s) _aloe_stringify(_s)

/** Fetch container object from a containing member object. */
#define aloe_container_of(_obj, _type, _member) \
	((_type *)((_obj) ? ((char*)(_obj) - offsetof(_type, _member)) : NULL))

/** String concatenate. */
#define _aloe_concat(_s1, _s2) _s1 ## _s2

/** String concatenate support macro expansion. */
#define aloe_concat(_s1, _s2) _aloe_concat(_s1, _s2)

#ifdef __GNUC__
#define aloe_offsetof(_s, _m) offsetof(_s, _m)
#else
#define aloe_offsetof(_s, _m) (((_s*)NULL)->_m)
#endif

/** Generic buffer holder. */
typedef struct aloe_buf_rec {
	void *data; /**< Memory pointer. */
	size_t cap; /**< Memory capacity. */
	size_t lmt; /**< Data size. */
	size_t pos; /**< Data start. */
} aloe_buf_t;

/**
 * fb.pos: Start of valid data
 * fb.lmt: Size of valid data
 *
 * @param fb
 * @param data
 * @param sz
 * @return
 */
size_t aloe_rinbuf_read(aloe_buf_t *buf, void *data, size_t sz);

/**
 * fb.pos: Start of spare
 * fb.lmt: Size of valid data
 *
 * @param fb
 * @param data
 * @param sz
 * @return
 */
size_t aloe_rinbuf_write(aloe_buf_t *buf, const void *data, size_t sz);

#define aloe_buf_clear(_buf) do {(_buf)->lmt = (_buf)->cap; (_buf)->pos = 0;} while (0)
#define aloe_buf_flip(_buf) do {(_buf)->lmt = (_buf)->pos; (_buf)->pos = 0;} while (0)

void aloe_buf_shift_left(aloe_buf_t *buf, size_t offset);

typedef enum aloe_buf_flag_enum {
	aloe_buf_flag_none = 0,
	aloe_buf_flag_retain_rinbuf,
	aloe_buf_flag_retain_index,
} aloe_buf_flag_t;

/**
 *
 * aloe_buf_flag_retain_pos will update lmt if lmt == cap
 *
 * @param buf
 * @param cap
 * @param retain
 * @return
 */
int aloe_buf_expand(aloe_buf_t *buf, size_t cap, aloe_buf_flag_t retain);

/**
 *
 * Update buf index when all fmt fulfill.
 *
 * @param buf
 * @param fmt
 * @param va
 * @return
 */
int aloe_buf_vprintf(aloe_buf_t *buf, const char *fmt, va_list va)
		__attribute__((format(printf, 2, 0)));
int aloe_buf_printf(aloe_buf_t *buf, const char *fmt, ...)
		__attribute__((format(printf, 2, 3)));

/**
 *
 * Malloc with max and buf.lmt == cap
 *
 * @param buf
 * @param max
 * @param fmt
 * @param va
 * @return
 */
int aloe_buf_vaprintf(aloe_buf_t *buf, ssize_t max, const char *fmt,
		va_list va) __attribute__((format(printf, 3, 0)));
int aloe_buf_aprintf(aloe_buf_t *buf, ssize_t max, const char *fmt, ...)
		__attribute__((format(printf, 3, 4)));

typedef struct aloe_mod_rec {
	const char *name;
	void* (*init)(void);
	void (*destroy)(void*);
	int (*ioctl)(void*, void*);
} aloe_mod_t;

/**
 *
 * @param f
 * @param fd fd=1 if f is file descriptor, otherwise assume f is path
 * @return
 */
ssize_t aloe_file_size(const void *f, int fd);

/** @} ALOE_EV_MISC */

/** @addtogroup ALOE_EV_TIME
 * @{
 */

/** Formalize time value. */
#define ALOE_TIMESEC_NORM(_sec, _subsec, _subscale) if ((_subsec) >= _subscale) { \
		(_sec) += (_subsec) / _subscale; \
		(_subsec) %= (_subscale); \
	}

/** Compare 2 time value. */
#define ALOE_TIMESEC_CMP(_a_sec, _a_subsec, _b_sec, _b_subsec) ( \
	((_a_sec) > (_b_sec)) ? 1 : \
	((_a_sec) < (_b_sec)) ? -1 : \
	((_a_subsec) > (_b_subsec)) ? 1 : \
	((_a_subsec) < (_b_subsec)) ? -1 : \
	0)

/** Subtraction for time value. */
#define ALOE_TIMESEC_SUB(_a_sec, _a_subsec, _b_sec, _b_subsec, _c_sec, \
		_c_subsec, _subscale) \
	if ((_a_subsec) < (_b_subsec)) { \
		(_c_sec) = (_a_sec) - (_b_sec) - 1; \
		(_c_subsec) = (_subscale) + (_a_subsec) - (_b_subsec); \
	} else { \
		(_c_sec) = (_a_sec) - (_b_sec); \
		(_c_subsec) = (_a_subsec) - (_b_subsec); \
	}

/** Addition for time value. */
#define ALOE_TIMESEC_ADD(_a_sec, _a_subsec, _b_sec, _b_subsec, _c_sec, \
		_c_subsec, _subscale) do { \
	(_c_sec) = (_a_sec) + (_b_sec); \
	(_c_subsec) = (_a_subsec) + (_b_subsec); \
	ALOE_TIMESEC_NORM(_c_sec, _c_subsec, _subscale); \
} while(0)

/** Normalize timeval.
 *
 * |a|
 *
 * @param a
 * @return (a)
 */
struct timeval* aloe_timeval_norm(struct timeval *a);

/** Compare timeval.
 *
 * |a - b|
 *
 * @param a A normalized timeval
 * @param b A normalized timeval
 * @return 1, -1 or 0 if (a) later/early/equal then/to (b)
 */
int aloe_timeval_cmp(const struct timeval *a, const struct timeval *b);

/** Subtraction timeval.
 *
 * c = a - b
 *
 * @param a A normalized timeval, must later then (b)
 * @param b A normalized timeval, must early then (a)
 * @param c Hold result if not NULL
 * @return (c)
 */
struct timeval* aloe_timeval_sub(const struct timeval *a, const struct timeval *b,
		struct timeval *c);

/** Addition timeval.
 *
 * c = a + b
 *
 * @param a
 * @param b
 * @param c
 * @return
 */
struct timeval* aloe_timeval_add(const struct timeval *a, const struct timeval *b,
		struct timeval *c);

/** @} ALOE_EV_TIME */

/** @addtogroup ALOE_EV_IO
 * @{
 */
/** Check the error number indicate nonblocking state. */
#define ALOE_ENO_NONBLOCKING(_e) ((_e) == EAGAIN || (_e) == EINPROGRESS)

/** Setup local socket address. */
int aloe_local_socket_address(struct sockaddr_un *sa, socklen_t *sa_len,
		const char *path);

int aloe_local_socker_listener(const char *path, int backlog,
		struct sockaddr_un *sa, socklen_t *sa_len);

/** Set nonblocking flag. */
int aloe_file_nonblock(int fd, int en);

/** Callback for notify event to user. */
typedef void (*aloe_ev_noti_cb_t)(int fd, unsigned ev_noti, void *cbarg);

/** Notify event to user. */
typedef struct aloe_ev_ctx_noti_rec {
	int fd;
	aloe_ev_noti_cb_t cb; /**< Callback to user. */
	void *cbarg; /**< Callback argument. */
	unsigned ev_wait; /**< Event to wait. */
	struct timespec due; /**< Monotonic timeout. */
	unsigned ev_noti; /**< Notified event. */
	TAILQ_ENTRY(aloe_ev_ctx_noti_rec) qent;
} aloe_ev_ctx_noti_t;

/** Queue of aloe_ev_noti_t. */
typedef TAILQ_HEAD(aloe_ev_ctx_noti_queue_rec, aloe_ev_ctx_noti_rec) aloe_ev_ctx_noti_queue_t;

/** FD for select(). */
typedef struct aloe_ev_ctx_fd_rec {
	int fd; /**< FD to monitor. */
	aloe_ev_ctx_noti_queue_t noti_q; /**< Queue of aloe_ev_noti_t for this FD. */
	TAILQ_ENTRY(aloe_ev_ctx_fd_rec) qent;
} aloe_ev_ctx_fd_t;

/** Queue of aloe_ev_fd_t. */
typedef TAILQ_HEAD(aloe_ev_ctx_fd_queue_rec, aloe_ev_ctx_fd_rec) aloe_ev_ctx_fd_queue_t;

/** Information about control flow and running context. */
typedef struct aloe_ev_ctx_rec {
	aloe_ev_ctx_fd_queue_t fd_q; /**< Queue to select(). */
	aloe_ev_ctx_fd_queue_t spare_fd_q; /**< Queue for cached memory. */
	aloe_ev_ctx_noti_queue_t noti_q; /**< Queue for ready to notify. */
	aloe_ev_ctx_noti_queue_t spare_noti_q; /**< Queue for cached memory. */
} aloe_ev_ctx_t;

/** @} ALOE_EV_IO */

/** @addtogroup ALOE_EV_CFG
 * @{
 */

typedef enum aloe_cfg_type_enum {
	aloe_cfg_type_void = 0,
	aloe_cfg_type_int,
	aloe_cfg_type_uint,
	aloe_cfg_type_long,
	aloe_cfg_type_ulong,
	aloe_cfg_type_double,
	aloe_cfg_type_pointer,

	aloe_cfg_type_data, /**< set( ,const void*, size_t) */
	aloe_cfg_type_string, /**< set( ,const char*, ...) */
} aloe_cfg_type_t;

void* aloe_cfg_init(void);
void aloe_cfg_destroy(void*);

/**
 *
 * !key && type == aloe_cfg_type_void -> reset all cfg
 *
 * @param
 * @param
 * @param
 */
void* aloe_cfg_set(void*, const char*, aloe_cfg_type_t, ...);

/**
 *
 * !key -> return first iter
 *
 * @param
 * @param
 */
void* aloe_cfg_find(void*, const char*);

/**
 *
 * !prev -> return first iter
 *
 * @param
 * @param
 */
void* aloe_cfg_next(void*, void*);
const char* aloe_cfg_key(void*);
aloe_cfg_type_t aloe_cfg_type(void*);
int aloe_cfg_int(void*);
unsigned aloe_cfg_uint(void*);
long aloe_cfg_long(void*);
unsigned long aloe_cfg_ulong(void*);
double aloe_cfg_double(void*);
void* aloe_cfg_pointer(void*);
const aloe_buf_t* aloe_cfg_data(void*);

/** @} ALOE_EV_CFG */

#ifdef __cplusplus
} // extern "C"
#endif

#endif /* _H_ALOE_EV_PRIV */
