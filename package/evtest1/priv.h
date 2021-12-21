/**
 * @author joelai
 */

#ifndef _H_ALOE_EV_PRIV
#define _H_ALOE_EV_PRIV

#include <compat/openbsd/sys/tree.h>
#include <compat/openbsd/sys/queue.h>

#include <aloe/ev.h>

/** @defgroup ALOE_EV_INTERNAL Internal
 * @brief Internal utility.
 *
 * @defgroup ALOE_EV_MISC Miscellaneous
 * @ingroup ALOE_EV_INTERNAL
 * @brief Utility for trivial operation.
 *
 * @defgroup ALOE_EV_TIME Time
 * @ingroup ALOE_EV_INTERNAL
 * @brief Utility to manipulate time.
 *
 * @defgroup ALOE_EV_SOCKET Socket and file
 * @ingroup ALOE_EV_INTERNAL
 * @brief Utility to manipulate socket and file.
 *
 */

#ifdef __cplusplus
extern "C" {
#endif

/** @addtogroup ALOE_EV_MISC
 * @{
 */

#define aloe_trex "🦖"
#define aloe_sauropod "🦕"
#define aloe_lizard "🦎"

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

typedef struct aloe_fb_rec {
	void *data;
	size_t cap, lmt, pos;
} aloe_fb_t;

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

/** @addtogroup ALOE_EV_SOCKET
 * @{
 */
/** Check the error number indicate nonblocking state. */
#define ALOE_ENO_NONBLOCKING(_e) ((_e) == EAGAIN || (_e) == EINPROGRESS)

/** Setup local socket address. */
int aloe_local_socket_address(struct sockaddr_un *sa, socklen_t *sa_len,
		const char *path);

/** Set nonblocking flag. */
int aloe_file_nonblock(int fd, int en);

/** Information for notify event to user. */
typedef struct aloe_ev_noti_rec {
	void (*cb)(int fd, unsigned ev_noti, void *cbarg); /**< Callback when event triggered */
	void *cbarg;
	unsigned ev_wait; /**< Event to wait. */
	struct timespec due; /**< Monotonic timeout. */
	unsigned ev_noti; /**< Notified event. */
	TAILQ_ENTRY(aloe_ev_noti_rec) qent;
} aloe_ev_noti_t;

typedef TAILQ_HEAD(aloe_ev_noti_queue_rec, aloe_ev_noti_rec) aloe_ev_noti_queue_t;

/** Information about FD for select(). */
typedef struct aloe_ev_fd_rec {
	int fd; /**< FD to monitor */
	aloe_ev_noti_queue_t noti_q;
	TAILQ_ENTRY(aloe_ev_fd_rec) qent;
} aloe_ev_fd_t;

typedef TAILQ_HEAD(aloe_ev_fd_queue_rec, aloe_ev_fd_rec) aloe_ev_fd_queue_t;

/** Information about control flow and running context. */
typedef struct aloe_ev_ctx_rec {
	aloe_ev_fd_queue_t fd_q, spare_fd_q, noti_fd_q;
	aloe_ev_noti_queue_t spare_noti_q;
} aloe_ev_ctx_t;

/** @} ALOE_EV_SOCKET */

#ifdef __cplusplus
} // extern "C"
#endif

#endif /* _H_ALOE_EV_PRIV */
