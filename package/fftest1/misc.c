/* 
 * @author joelai
 */

#include "priv.h"

size_t aloe_rinbuf_read(aloe_buf_t *buf, void *data, size_t sz) {
	size_t rw_sz, ret_sz;

	if (sz > buf->lmt) sz = buf->lmt;
	ret_sz = sz;

	// rinbuf max continuous readable size: min(lmt, (cap - pos))
	while ((rw_sz = aloe_min(sz, buf->cap - buf->pos)) > 0) {
		memcpy(data, (char*)buf->data + buf->pos, rw_sz);
		buf->pos = (buf->pos + rw_sz) % buf->cap;
		buf->lmt -= rw_sz;
		if (rw_sz >= sz) break;
		sz -= rw_sz;
		data = (char*)data + rw_sz;
	}
	return ret_sz;
}

size_t aloe_rinbuf_write(aloe_buf_t *buf, const void *data, size_t sz) {
	size_t rw_sz, ret_sz;

	ret_sz = aloe_min(sz, buf->cap - buf->lmt);

	// rinbuf max continuous writable position: wpos = ((pos + lmt) % cap)
	while ((rw_sz = aloe_min(sz, buf->cap - buf->lmt)) > 0) {
		int rw_pos = (buf->pos + buf->lmt) % buf->cap;
		if (rw_sz > buf->cap - rw_pos) rw_sz = buf->cap - rw_pos;
		memcpy((char*)buf->data + rw_pos, data, rw_sz);
		buf->lmt += rw_sz;
		if (rw_sz >= sz) break;
		sz -= rw_sz;
		data = (char*)data + rw_sz;
	}
	return ret_sz;
}

void aloe_buf_shift_left(aloe_buf_t *buf, size_t offset) {
	if (!buf->data || offset > buf->pos || buf->pos > buf->lmt) return;
	memmove(buf->data, (char*)buf->data + offset, buf->pos - offset);
	buf->pos -= offset;
	buf->lmt -= offset;
}

int aloe_buf_expand(aloe_buf_t *buf, size_t cap, aloe_buf_flag_t retain) {
	void *data;

	if (cap <= 0 || buf->cap >= cap) return 0;
	if (!(data = malloc(cap))) return ENOMEM;
	if (buf->data) {
		if (retain == aloe_buf_flag_retain_rinbuf) {
			aloe_rinbuf_read(buf, data, buf->lmt);
			buf->pos = 0;
		} else if (retain == aloe_buf_flag_retain_index) {
			memcpy(data, (char*)buf->data, buf->pos);
			if (buf->lmt == buf->cap) buf->lmt = cap;
		}
		free(buf->data);
	}
	buf->data = data;
	buf->cap = cap;
	return 0;
}

int aloe_buf_vprintf(aloe_buf_t *buf, const char *fmt, va_list va) {
	int r;

	r = vsnprintf((char*)buf->data + buf->pos, buf->lmt - buf->pos, fmt, va);
	if (r < 0 || r >= buf->lmt - buf->pos) return 0;
	buf->pos += r;
	return r;
}

int aloe_buf_printf(aloe_buf_t *buf, const char *fmt, ...) {
	int r;
	va_list va;

	if (!fmt) return 0;
	va_start(va, fmt);
	r = aloe_buf_vprintf(buf, fmt, va);
	va_end(va);
	return r;
}

int aloe_buf_vaprintf(aloe_buf_t *buf, ssize_t max, const char *fmt,
		va_list va) {
	int r, marked;

	if (!fmt || !fmt[0]) return 0;

	if (max == 0 || buf->lmt != buf->cap) {
		return aloe_buf_vprintf(buf, fmt, va);
	}
	if (aloe_buf_expand(buf, ((max > 0 && max < 32) ? max : 32),
			aloe_buf_flag_retain_index) != 0) {
		return 0;
	}

	while (1) {
		va_list vb;

#if __STDC_VERSION__ < 199901L
#  warning "va_copy() may require C99"
#endif
		va_copy(vb, va);
		r = aloe_buf_vprintf(buf, fmt, vb);
		if (r < 0 || r >= buf->cap) {
			if (max > 0 && buf->cap >= max) return -1;
			r = buf->cap * 2;
			if (max > 0 && r > max) r = max;
			if (aloe_buf_expand(buf, r, aloe_buf_flag_retain_index) != 0) {
				va_end(vb);
				return 0;
			}
			va_end(vb);
			continue;
		}
		va_end(vb);
		return r;
	};
}

int aloe_buf_aprintf(aloe_buf_t *buf, ssize_t max, const char *fmt, ...) {
	int r;
	va_list va;

	if (!fmt) return 0;
	va_start(va, fmt);
	r = aloe_buf_vaprintf(buf, max, fmt, va);
	va_end(va);
	return r;
}

